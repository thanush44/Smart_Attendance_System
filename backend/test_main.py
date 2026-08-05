import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
import pyotp
import json

from database import Base, get_db
from main import app, SECRET_KEY

# In-memory SQLite database configuration for tests
# Local file SQLite database for testing (avoids connection pooling issues of :memory:)
import os
SQLALCHEMY_DATABASE_URL = "sqlite:///./test_attendance.db"

engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Override the dependency to use in-memory database
def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

client = TestClient(app)

@pytest.fixture(autouse=True)
def setup_database():
    # Setup database schema before each test
    Base.metadata.create_all(bind=engine)
    yield
    # Tear down database schema after each test
    Base.metadata.drop_all(bind=engine)

def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"message": "Smart Attendance API is running!"}

def test_user_registration_and_login():
    # 1. Register student
    reg_response = client.post("/auth/register", json={
        "username": "student123",
        "password": "mypassword1",
        "name": "Jane Doe",
        "role": "student",
        "face_embedding": "[0.1, -0.2, 0.3]"
      })
    assert reg_response.status_code == 200
    assert reg_response.json()["username"] == "student123"
    assert reg_response.json()["role"] == "student"

    # 2. Login student
    login_response = client.post("/auth/login", json={
        "username": "student123",
        "password": "mypassword1"
    })
    assert login_response.status_code == 200
    assert "access_token" in login_response.json()
    assert login_response.json()["user"]["name"] == "Jane Doe"
    assert login_response.json()["user"]["face_embedding"] == "[0.1, -0.2, 0.3]"

def test_teacher_register_create_class_start_session():
    # 1. Register teacher
    client.post("/auth/register", json={
        "username": "profsmith",
        "password": "profpassword",
        "name": "Prof. Smith",
        "role": "teacher"
    })

    # Login to get teacher details (id)
    login_res = client.post("/auth/login", json={
        "username": "profsmith",
        "password": "profpassword"
    })
    teacher_id = login_res.json()["user"]["id"]

    # 2. Create Class
    class_res = client.post("/classes/create", json={
        "name": "Mobile Development",
        "code": "CS-302",
        "teacher_id": teacher_id
    })
    assert class_res.status_code == 200
    class_id = class_res.json()["id"]

    # 3. Start Session
    session_res = client.post("/sessions/start", json={
        "class_id": class_id
    })
    assert session_res.status_code == 200
    assert session_res.json()["class_name"] == "Mobile Development"
    assert "ble_uuid" in session_res.json()
    assert "otp_secret" in session_res.json()

def test_attendance_submission_with_otp():
    # Setup teacher & class
    client.post("/auth/register", json={"username": "prof", "password": "pw", "name": "Prof", "role": "teacher"})
    t_login = client.post("/auth/login", json={"username": "prof", "password": "pw"}).json()
    t_id = t_login["user"]["id"]
    
    cls = client.post("/classes/create", json={"name": "Algos", "code": "CS-201", "teacher_id": t_id}).json()
    cls_id = cls["id"]
    cls_code = cls["code"]

    # Setup student and enroll
    client.post("/auth/register", json={"username": "std", "password": "pw", "name": "Std", "role": "student"})
    s_login = client.post("/auth/login", json={"username": "std", "password": "pw"}).json()
    s_id = s_login["user"]["id"]

    # Enroll in class
    enroll_res = client.post("/classes/enroll", json={"student_id": s_id, "class_code": cls_code})
    assert enroll_res.status_code == 200

    # Start session
    session = client.post("/sessions/start", json={"class_id": cls_id}).json()
    session_id = session["session_id"]
    otp_secret = session["otp_secret"]

    # Generate valid rolling OTP token
    totp = pyotp.TOTP(otp_secret, interval=10)
    valid_token = totp.now()

    # 1. Submit attendance with invalid OTP
    bad_att = client.post("/attendance/submit", json={
        "session_id": session_id,
        "student_id": s_id,
        "otp_token": "000000",
        "verified_proximity": True,
        "verified_face": True
    })
    assert bad_att.status_code == 400
    assert "Invalid or expired QR code token" in bad_att.json()["detail"]

    # 2. Submit attendance with valid credentials
    good_att = client.post("/attendance/submit", json={
        "session_id": session_id,
        "student_id": s_id,
        "otp_token": valid_token,
        "verified_proximity": True,
        "verified_face": True
    })
    assert good_att.status_code == 200
    assert good_att.json()["message"] == "Attendance marked successfully!"

from fastapi import FastAPI, Depends, HTTPException, status, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
import uuid
import datetime
import pyotp
import json
from typing import List, Dict
from jose import JWTError, jwt
import bcrypt
from pydantic import BaseModel, Field

import models
from database import engine, get_db

# Create the database tables
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="Smart Attendance Backend")

# Enable CORS for frontend web dashboards
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

SECRET_KEY = "super_secret_key_for_smart_attendance_tokens_and_jwt"
ALGORITHM = "HS256"

# Pydantic schemas for requests
class UserRegister(BaseModel):
    username: str
    password: str
    name: str
    role: str = Field(description="Must be 'student' or 'teacher'")
    face_embedding: str = None  # JSON string representation of embedding array

class UserLogin(BaseModel):
    username: str
    password: str

class ClassCreate(BaseModel):
    name: str
    code: str
    teacher_id: int

class EnrollRequest(BaseModel):
    student_id: int
    class_code: str

class StartSessionRequest(BaseModel):
    class_id: int

class AttendanceSubmit(BaseModel):
    session_id: int
    student_id: int
    otp_token: str
    verified_proximity: bool
    verified_face: bool

# Active WebSocket connections grouped by session_id
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[int, List[WebSocket]] = {}

    async def connect(self, session_id: int, websocket: WebSocket):
        await websocket.accept()
        if session_id not in self.active_connections:
            self.active_connections[session_id] = []
        self.active_connections[session_id].append(websocket)

    def disconnect(self, session_id: int, websocket: WebSocket):
        if session_id in self.active_connections:
            self.active_connections[session_id].remove(websocket)
            if not self.active_connections[session_id]:
                del self.active_connections[session_id]

    async def broadcast_to_session(self, session_id: int, message: dict):
        if session_id in self.active_connections:
            for connection in self.active_connections[session_id]:
                try:
                    await connection.send_text(json.dumps(message))
                except Exception:
                    # Connection might be dead
                    pass

manager = ConnectionManager()

# Helper Authentication functions
def get_password_hash(password: str) -> str:
    pwd_bytes = password.encode('utf-8')
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(pwd_bytes, salt)
    return hashed.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    pwd_bytes = plain_password.encode('utf-8')
    hashed_bytes = hashed_password.encode('utf-8')
    return bcrypt.checkpw(pwd_bytes, hashed_bytes)

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.datetime.utcnow() + datetime.timedelta(hours=24)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

# --- ROUTES ---

@app.get("/")
def read_root():
    return {"message": "Smart Attendance API is running!"}

@app.post("/auth/register")
def register(user_data: UserRegister, db: Session = Depends(get_db)):
    # Check if user already exists
    existing = db.query(models.User).filter(models.User.username == user_data.username).first()
    if existing:
        raise HTTPException(status_code=400, detail="Username already registered")
    
    if user_data.role not in ["student", "teacher"]:
        raise HTTPException(status_code=400, detail="Role must be 'student' or 'teacher'")

    hashed_pw = get_password_hash(user_data.password)
    new_user = models.User(
        username=user_data.username,
        name=user_data.name,
        hashed_password=hashed_pw,
        role=user_data.role,
        face_embedding=user_data.face_embedding
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return {"id": new_user.id, "username": new_user.username, "role": new_user.role, "message": "User registered successfully"}

@app.post("/auth/login")
def login(login_data: UserLogin, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == login_data.username).first()
    if not user or not verify_password(login_data.password, user.hashed_password):
        raise HTTPException(status_code=400, detail="Incorrect username or password")
    
    token = create_access_token({"sub": user.username, "role": user.role, "id": user.id})
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "username": user.username,
            "name": user.name,
            "role": user.role,
            "face_embedding": user.face_embedding
        }
    }

@app.post("/classes/create")
def create_class(class_data: ClassCreate, db: Session = Depends(get_db)):
    # Check if code unique
    existing = db.query(models.Class).filter(models.Class.code == class_data.code).first()
    if existing:
        raise HTTPException(status_code=400, detail="Class code already exists")
    
    teacher = db.query(models.User).filter(models.User.id == class_data.teacher_id, models.User.role == "teacher").first()
    if not teacher:
        raise HTTPException(status_code=400, detail="Teacher not found")

    new_class = models.Class(
        name=class_data.name,
        code=class_data.code,
        teacher_id=class_data.teacher_id
    )
    db.add(new_class)
    db.commit()
    db.refresh(new_class)
    return new_class

@app.post("/classes/enroll")
def enroll_class(enroll_data: EnrollRequest, db: Session = Depends(get_db)):
    student = db.query(models.User).filter(models.User.id == enroll_data.student_id, models.User.role == "student").first()
    if not student:
        raise HTTPException(status_code=400, detail="Student not found")
    
    classroom = db.query(models.Class).filter(models.Class.code == enroll_data.class_code).first()
    if not classroom:
        raise HTTPException(status_code=404, detail="Class not found")

    if classroom in student.classes_enrolled:
        return {"message": "Already enrolled in class"}
    
    student.classes_enrolled.append(classroom)
    db.commit()
    return {"message": f"Enrolled successfully in {classroom.name}"}

@app.get("/users/{user_id}/classes")
def get_user_classes(user_id: int, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    if user.role == "teacher":
        return user.classes_taught
    else:
        return user.classes_enrolled

@app.post("/sessions/start")
def start_session(session_req: StartSessionRequest, db: Session = Depends(get_db)):
    classroom = db.query(models.Class).filter(models.Class.id == session_req.class_id).first()
    if not classroom:
        raise HTTPException(status_code=404, detail="Class not found")

    # Close any other active session for this class
    active_sessions = db.query(models.Session).filter(
        models.Session.class_id == session_req.class_id,
        models.Session.is_active == True
    ).all()
    for s in active_sessions:
        s.is_active = False
    
    # Generate unique UUID for BLE proximity advertising (from Teacher Phone)
    ble_uuid = str(uuid.uuid4())
    
    # Generate a random base32 OTP secret key
    otp_secret = pyotp.random_base32()

    new_session = models.Session(
        class_id=session_req.class_id,
        ble_uuid=ble_uuid,
        otp_secret=otp_secret,
        is_active=True
    )
    db.add(new_session)
    db.commit()
    db.refresh(new_session)

    return {
        "session_id": new_session.id,
        "class_id": new_session.class_id,
        "class_name": classroom.name,
        "ble_uuid": new_session.ble_uuid,
        "otp_secret": new_session.otp_secret,
        "is_active": new_session.is_active
    }

@app.post("/attendance/submit")
async def submit_attendance(att_data: AttendanceSubmit, db: Session = Depends(get_db)):
    session = db.query(models.Session).filter(models.Session.id == att_data.session_id).first()
    if not session or not session.is_active:
        raise HTTPException(status_code=400, detail="Active class session not found")

    student = db.query(models.User).filter(models.User.id == att_data.student_id, models.User.role == "student").first()
    if not student:
        raise HTTPException(status_code=400, detail="Student not found")

    # Check if student is enrolled in this class
    classroom = db.query(models.Class).filter(models.Class.id == session.class_id).first()
    if classroom not in student.classes_enrolled:
        raise HTTPException(status_code=400, detail="Student is not enrolled in this class")

    # Check if student already marked present
    already_marked = db.query(models.Attendance).filter(
        models.Attendance.session_id == att_data.session_id,
        models.Attendance.student_id == att_data.student_id
    ).first()
    if already_marked:
        return {"message": "Attendance already marked", "status": already_marked.status}

    # Validate Dynamic Time-based OTP (Token changes every 10 seconds)
    totp = pyotp.TOTP(session.otp_secret, interval=10)
    # Allow 1 step (10 seconds) drift in either direction to handle minor network/clock sync delays
    is_valid_otp = totp.verify(att_data.otp_token, valid_window=1)

    if not is_valid_otp:
        raise HTTPException(status_code=400, detail="Invalid or expired QR code token")

    if not att_data.verified_proximity:
        raise HTTPException(status_code=400, detail="Proximity check failed. You must be in the classroom.")

    if not att_data.verified_face:
        raise HTTPException(status_code=400, detail="Face recognition verification failed.")

    # Log successful attendance
    new_att = models.Attendance(
        session_id=att_data.session_id,
        student_id=att_data.student_id,
        verified_proximity=True,
        verified_face=True,
        status="present"
    )
    db.add(new_att)
    db.commit()
    db.refresh(new_att)

    # Broadcast check-in confirmation to the websocket room for the projector UI
    await manager.broadcast_to_session(session.id, {
        "type": "student_checkin",
        "student_id": student.id,
        "student_name": student.name,
        "student_username": student.username,
        "timestamp": str(new_att.timestamp)
    })

    return {"message": "Attendance marked successfully!", "status": "present"}

@app.get("/sessions/{session_id}/attendance")
def get_session_attendance(session_id: int, db: Session = Depends(get_db)):
    records = db.query(models.Attendance).filter(models.Attendance.session_id == session_id).all()
    response = []
    for r in records:
        response.append({
            "student_id": r.student_id,
            "student_name": r.student.name,
            "student_username": r.student.username,
            "timestamp": r.timestamp,
            "verified_face": r.verified_face,
            "verified_proximity": r.verified_proximity
        })
    return response

# --- WEBSOCKET FOR PROJECTOR DASHBOARD ---
@app.websocket("/ws/class/{session_id}")
async def websocket_endpoint(websocket: WebSocket, session_id: int, db: Session = Depends(get_db)):
    await manager.connect(session_id, websocket)
    
    # Verify session exists
    session = db.query(models.Session).filter(models.Session.id == session_id).first()
    if not session:
        await websocket.send_text(json.dumps({"error": "Invalid session ID"}))
        manager.disconnect(session_id, websocket)
        return

    # Start sending rolling OTP codes every second to the dashboard
    totp = pyotp.TOTP(session.otp_secret, interval=10)
    
    try:
        # Send initial state: currently checked-in students
        existing_checkins = db.query(models.Attendance).filter(models.Attendance.session_id == session_id).all()
        checkins_list = [{
            "student_id": c.student_id,
            "student_name": c.student.name,
            "student_username": c.student.username,
            "timestamp": str(c.timestamp)
        } for c in existing_checkins]

        await websocket.send_text(json.dumps({
            "type": "init",
            "class_name": session.classroom.name,
            "class_code": session.classroom.code,
            "ble_uuid": session.ble_uuid,
            "checkins": checkins_list
        }))

        # Periodically push the active token.
        # Front-end will check if token changed and redraw QR.
        while True:
            # Generate the active OTP token for this moment
            current_token = totp.now()
            
            # Send message
            await websocket.send_text(json.dumps({
                "type": "otp_update",
                "token": current_token,
                "expires_in": 10 - (int(datetime.datetime.utcnow().timestamp()) % 10)
            }))
            
            # Sleep for 1 second before generating next token tick
            import asyncio
            await asyncio.sleep(1)

    except WebSocketDisconnect:
        manager.disconnect(session_id, websocket)
    except Exception as e:
        manager.disconnect(session_id, websocket)

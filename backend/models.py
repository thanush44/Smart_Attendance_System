from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey, Table
from sqlalchemy.orm import relationship
import datetime
from database import Base

# Association table for Student enrollment in Classes
enrollment_table = Table(
    "enrollments",
    Base.metadata,
    Column("student_id", Integer, ForeignKey("users.id"), primary_key=True),
    Column("class_id", Integer, ForeignKey("classes.id"), primary_key=True)
)

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=False)
    hashed_password = Column(String, nullable=False)
    role = Column(String, nullable=False)  # "student" or "teacher"
    
    # Store a serialized JSON string representing the face embedding (e.g. 128 float array)
    # This allows on-device facial matching with cloud-synced templates.
    face_embedding = Column(String, nullable=True)

    # Relationships
    classes_taught = relationship("Class", back_populates="teacher")
    classes_enrolled = relationship("Class", secondary=enrollment_table, back_populates="students")
    attendance_records = relationship("Attendance", back_populates="student")

class Class(Base):
    __tablename__ = "classes"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    code = Column(String, unique=True, index=True, nullable=False)  # e.g., CS-101
    teacher_id = Column(Integer, ForeignKey("users.id"), nullable=False)

    # Relationships
    teacher = relationship("User", back_populates="classes_taught")
    students = relationship("User", secondary=enrollment_table, back_populates="classes_enrolled")
    sessions = relationship("Session", back_populates="classroom")

class Session(Base):
    __tablename__ = "sessions"

    id = Column(Integer, primary_key=True, index=True)
    class_id = Column(Integer, ForeignKey("classes.id"), nullable=False)
    start_time = Column(DateTime, default=datetime.datetime.utcnow)
    is_active = Column(Boolean, default=True)
    
    # BLE proximity UUID broadcasted by the teacher's phone for this session
    ble_uuid = Column(String, nullable=False)
    
    # Secret key used to generate TOTP (rolling QR codes) for this session
    otp_secret = Column(String, nullable=False)

    # Relationships
    classroom = relationship("Class", back_populates="sessions")
    attendance_records = relationship("Attendance", back_populates="session")

class Attendance(Base):
    __tablename__ = "attendance"

    id = Column(Integer, primary_key=True, index=True)
    session_id = Column(Integer, ForeignKey("sessions.id"), nullable=False)
    student_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    timestamp = Column(DateTime, default=datetime.datetime.utcnow)
    status = Column(String, default="present")  # "present", "late", "absent"
    
    verified_proximity = Column(Boolean, default=False)
    verified_face = Column(Boolean, default=False)

    # Relationships
    session = relationship("Session", back_populates="attendance_records")
    student = relationship("User", back_populates="attendance_records")

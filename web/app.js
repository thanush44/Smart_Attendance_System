// --- FIREBASE CONFIGURATION ---
// TODO: Replace this placeholder config with your actual Firebase Web Config keys.
// You can get this by going to Firebase Console > Project Settings > Web App (Add App).
const firebaseConfig = {
    apiKey: "AIzaSyA7Ic4y9MRfTymEY5uoZmgHmvKwuoaSDa4",
    authDomain: "smart-attendence-16c63.firebaseapp.com",
    projectId: "smart-attendence-16c63",
    storageBucket: "smart-attendence-16c63.firebasestorage.app",
    messagingSenderId: "5109015283",
    appId: "1:5109015283:web:cd24045fcc912956154d86",
    measurementId: "G-8K4ZWV7BM6"
};

// Initialize Firebase compatibility SDKs
firebase.initializeApp(firebaseConfig);
const db = firebase.firestore();

// Global state
let currentToken = null;
let currentSessionId = null;
let otpInterval = null;
let unsubscribeAttendance = null;
let unsubscribeSession = null;

// DOM Elements
const classTitleEl = document.getElementById("class-name");
const classCodeEl = document.getElementById("class-code");
const bleUuidEl = document.getElementById("ble-uuid");
const qrcodeContainer = document.getElementById("qrcode");
const expiryTimerEl = document.getElementById("expiry-timer");
const expiryBarEl = document.getElementById("expiry-bar");
const presentCountEl = document.getElementById("present-count");
const studentsGrid = document.getElementById("students-grid");
const emptyStateEl = document.getElementById("empty-state");
const connectionStatusEl = document.getElementById("connection-status");
const sessionInput = document.getElementById("session-input");
const loadBtn = document.getElementById("load-btn");
const closeSessionBtn = document.getElementById("close-session-btn");

// Initialize page
window.addEventListener("DOMContentLoaded", () => {
    // Check if session_id is in URL query parameters (e.g., ?session_id=docIdStr)
    const urlParams = new URLSearchParams(window.location.search);
    const sessionId = urlParams.get("session_id");
    
    if (sessionId) {
        sessionInput.value = sessionId;
        connectToSession(sessionId);
    }
});

// Manual connection trigger
loadBtn.addEventListener("click", () => {
    const sessionId = sessionInput.value.trim();
    if (sessionId) {
        // Update URL query parameter without refreshing page
        const newurl = window.location.protocol + "//" + window.location.host + window.location.pathname + `?session_id=${sessionId}`;
        window.history.pushState({path:newurl}, '', newurl);
        
        connectToSession(sessionId);
    } else {
        alert("Please enter a valid Session Document ID.");
    }
});

// Connect to Firestore Session and set up real-time listener
// Gracefully handle deactivation of active session
function handleSessionEnded() {
    if (otpInterval) clearInterval(otpInterval);
    otpInterval = null;
    currentToken = null;
    
    classCodeEl.innerText = "Session Ended";
    connectionStatusEl.className = "text-sm font-semibold text-rose-500 flex items-center gap-2 justify-end";
    connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Session Closed`;
    
    // Hide Close Session button
    if (closeSessionBtn) closeSessionBtn.style.display = "none";
    
    qrcodeContainer.innerHTML = `
        <div class="text-rose-400 text-center py-8">
            <i class="fa-solid fa-circle-xmark text-5xl block mb-3 animate-bounce"></i>
            <span class="font-bold text-lg block">Attendance Closed</span>
            <span class="text-xs text-gray-400">The teacher has ended this session.</span>
        </div>
    `;
    
    if (unsubscribeAttendance) {
        unsubscribeAttendance();
        unsubscribeAttendance = null;
    }
    if (unsubscribeSession) {
        unsubscribeSession();
        unsubscribeSession = null;
    }
}

// Connect to Firestore Session and set up real-time listener
async function connectToSession(sessionId) {
    // Clean up previous listeners & intervals
    if (otpInterval) clearInterval(otpInterval);
    if (unsubscribeAttendance) unsubscribeAttendance();
    if (unsubscribeSession) unsubscribeSession();
    
    // Set status to connecting
    connectionStatusEl.className = "text-sm font-semibold text-amber-500 flex items-center gap-2 justify-end";
    connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-amber-500 animate-pulse"></span> Connecting to Firestore...`;
    
    // Clear student grid and count
    studentsGrid.innerHTML = "";
    presentCountEl.innerText = "0";
    showEmptyState();
    
    try {
        let docId = sessionId;
        
        // If the code entered is a 6-character short PIN, resolve it to the active document ID first
        if (sessionId.length === 6) {
            connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-amber-500 animate-pulse"></span> Resolving Session PIN...`;
            const querySnapshot = await db.collection("sessions")
                .where("short_id", "==", sessionId)
                .where("is_active", "==", true)
                .limit(1)
                .get();
                
            if (querySnapshot.empty) {
                alert("No active session found matching PIN: " + sessionId);
                connectionStatusEl.className = "text-sm font-semibold text-rose-500 flex items-center gap-2 justify-end";
                connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Active PIN Not Found`;
                qrcodeContainer.innerHTML = `<div class="text-rose-400 text-center"><i class="fa-solid fa-triangle-exclamation text-4xl block mb-2"></i> PIN Not Found or Expired</div>`;
                return;
            }
            
            docId = querySnapshot.docs[0].id;
        }

        currentSessionId = docId;

        // Start listening to the Session Document in real time
        unsubscribeSession = db.collection("sessions").doc(docId)
            .onSnapshot((sessionDoc) => {
                if (!sessionDoc.exists) {
                    handleSessionEnded();
                    return;
                }
                
                const sessionData = sessionDoc.data();
                if (!sessionData.is_active) {
                    handleSessionEnded();
                    return;
                }
                
                // Render class info
                classTitleEl.innerText = sessionData.class_name;
                classCodeEl.innerText = "Session Active";
                bleUuidEl.innerText = sessionData.ble_uuid;

                // Show Close Session button
                if (closeSessionBtn) closeSessionBtn.style.display = "flex";

                // Get start time
                let startTime = null;
                if (sessionData.start_time) {
                    startTime = sessionData.start_time.toDate();
                }

                // Initialize client-side TOTP loop if not already started
                if (!otpInterval) {
                    connectionStatusEl.className = "text-sm font-semibold text-emerald-500 flex items-center gap-2 justify-end";
                    connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-emerald-500"></span> Connected to Cloud`;
                    
                    const totp = new OTPAuth.TOTP({
                        secret: OTPAuth.Secret.fromBase32(sessionData.otp_secret),
                        period: 10,
                        digits: 6
                    });

                    otpInterval = setInterval(() => {
                        const nowSeconds = Math.floor(Date.now() / 1000);
                        const expiresIn = 10 - (nowSeconds % 10);
                        const token = totp.generate();
                        
                        // Draw QR code if token changes
                        if (currentToken !== token) {
                            currentToken = token;
                            renderQRCode(token);
                        }
                        
                        updateCountdown(expiresIn);

                        // Check 3-minute auto-termination
                        if (startTime) {
                            const elapsed = Math.floor((Date.now() - startTime.getTime()) / 1000);
                            const remaining = 180 - elapsed;
                            if (remaining <= 0) {
                                clearInterval(otpInterval);
                                otpInterval = null;
                                db.collection("sessions").doc(docId).update({ is_active: false }).then(() => {
                                    handleSessionEnded();
                                });
                            } else {
                                const mins = Math.floor(remaining / 60);
                                const secs = remaining % 60;
                                const timeStr = `${mins}:${secs < 10 ? '0' : ''}${secs}`;
                                classCodeEl.innerText = `Session Active (Auto-closes in ${timeStr})`;
                            }
                        }
                    }, 1000);
                }

                // Start listening to the attendance collection for this session ID
                if (!unsubscribeAttendance) {
                    unsubscribeAttendance = db.collection("attendance")
                        .where("session_id", "==", docId)
                        .orderBy("timestamp", "asc")
                        .onSnapshot((snapshot) => {
                            snapshot.docChanges().forEach((change) => {
                                if (change.type === "added") {
                                    hideEmptyState();
                                    const checkin = change.doc.data();
                                    
                                    let timeStr = "";
                                    if (checkin.timestamp) {
                                        const date = checkin.timestamp.toDate();
                                        timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
                                    } else {
                                        timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
                                    }

                                    addStudentToGrid({
                                        student_id: checkin.student_id,
                                        student_name: checkin.student_name,
                                        student_username: checkin.student_username,
                                        time_str: timeStr
                                    });
                                }
                            });
                        }, (err) => {
                            console.error("Firestore listening error: ", err);
                        });
                }
            }, (err) => {
                console.error("Session snapshot error:", err);
                connectionStatusEl.className = "text-sm font-semibold text-rose-500 flex items-center gap-2 justify-end";
                connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Connection Error`;
            });

    } catch (e) {
        console.error("Failed to load session details: ", e);
        connectionStatusEl.className = "text-sm font-semibold text-rose-500 flex items-center gap-2 justify-end";
        connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Connection Error`;
    }
}

// Render dynamic QR code containing session data
function renderQRCode(token) {
    qrcodeContainer.innerHTML = ""; // Clear previous QR
    
    // Payload scanned by student contains the session ID and OTP token
    const payload = JSON.stringify({
        session_id: currentSessionId,
        token: token
    });
    
    // Create new QR Code
    new QRCode(qrcodeContainer, {
        text: payload,
        width: 240,
        height: 240,
        colorDark : "#0d0b14",
        colorLight : "#ffffff",
        correctLevel : QRCode.CorrectLevel.H
    });
}

// Update the dynamic countdown UI (10s rolling)
function updateCountdown(expiresIn) {
    expiryTimerEl.innerText = `Refreshing in ${expiresIn}s`;
    
    const percentage = (expiresIn / 10) * 100;
    expiryBarEl.style.width = `${percentage}%`;
    
    if (expiresIn <= 3) {
        expiryBarEl.className = "bg-gradient-to-r from-rose-500 to-red-500 h-full w-full transition-all duration-1000 ease-linear";
        expiryTimerEl.className = "text-rose-400 font-bold animate-pulse";
    } else {
        expiryBarEl.className = "bg-gradient-to-r from-violet-500 to-indigo-500 h-full w-full transition-all duration-1000 ease-linear";
        expiryTimerEl.className = "text-violet-400";
    }
}

// Append checked-in student card to grid
function addStudentToGrid(student) {
    const existingCard = document.getElementById(`student-${student.student_id}`);
    if (existingCard) return;

    // Increment count
    const currentCount = parseInt(presentCountEl.innerText);
    presentCountEl.innerText = currentCount + 1;
    
    const initials = student.student_name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2);

    const card = document.createElement("div");
    card.id = `student-${student.student_id}`;
    card.className = "student-card glass-panel rounded-2xl p-4 flex items-center gap-3";
    
    card.innerHTML = `
        <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-violet-500/20 to-indigo-500/20 border border-violet-500/30 flex items-center justify-center text-sm font-bold text-violet-300">
            ${initials}
        </div>
        <div class="min-w-0 flex-grow">
            <h4 class="font-bold text-sm text-white truncate">${student.student_name}</h4>
            <div class="flex justify-between items-center mt-0.5">
                <span class="text-[10px] text-gray-500 font-medium font-mono truncate mr-2">${student.student_username}</span>
                <span class="text-[10px] text-emerald-400 font-semibold bg-emerald-500/10 px-1.5 py-0.5 rounded flex items-center gap-1 font-mono shrink-0">
                    <i class="fa-solid fa-clock text-[8px]"></i> ${student.time_str}
                </span>
            </div>
        </div>
    `;
    
    studentsGrid.appendChild(card);
}

// Show/hide helper functions
function showEmptyState() {
    emptyStateEl.style.display = "flex";
}

function hideEmptyState() {
    emptyStateEl.style.display = "none";
}

// Manual session termination from projector screen
if (closeSessionBtn) {
    closeSessionBtn.addEventListener("click", async () => {
        if (!currentSessionId) return;
        if (confirm("Are you sure you want to close this attendance session? Students will no longer be able to check in.")) {
            try {
                await db.collection("sessions").doc(currentSessionId).update({
                    is_active: false
                });
            } catch (e) {
                alert("Error closing session: " + e.message);
            }
        }
    });
}

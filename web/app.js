// --- FIREBASE CONFIGURATION ---
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
let enrolledStudentsCount = 0;
let audioEnabled = true;
let audioCtx = null;

// DOM Elements
const classTitleEl = document.getElementById("class-name");
const classCodeEl = document.getElementById("class-code");
const sessionBadgeEl = document.getElementById("session-badge");
const sessionPinDisplayEl = document.getElementById("session-pin-display");
const bleUuidEl = document.getElementById("ble-uuid");
const qrcodeContainer = document.getElementById("qrcode");
const laserBeamEl = document.getElementById("laser-beam");
const expiryTimerEl = document.getElementById("expiry-timer");
const expiryBarEl = document.getElementById("expiry-bar");
const presentRatioEl = document.getElementById("present-ratio");
const turnoutBarEl = document.getElementById("turnout-bar");
const studentsGrid = document.getElementById("students-grid");
const emptyStateEl = document.getElementById("empty-state");
const connectionStatusEl = document.getElementById("connection-status");
const sessionInput = document.getElementById("session-input");
const loadBtn = document.getElementById("load-btn");
const closeSessionBtn = document.getElementById("close-session-btn");

// Initialize page on load
window.addEventListener("DOMContentLoaded", () => {
    const urlParams = new URLSearchParams(window.location.search);
    const sessionId = urlParams.get("session_id");
    
    if (sessionId) {
        if (sessionInput) sessionInput.value = sessionId;
        connectToSession(sessionId, true);
    } else {
        resetToHomeState();
    }
});

// Fullscreen Presentation Mode Toggle (F11)
function toggleFullscreen() {
    if (!document.fullscreenElement) {
        document.documentElement.requestFullscreen().catch(err => {
            console.log("Error enabling fullscreen: ", err);
        });
    } else {
        if (document.exitFullscreen) {
            document.exitFullscreen();
        }
    }
}

// Web Audio API Synthetic Chime on Check-In
function playCheckinChime() {
    if (!audioEnabled) return;
    try {
        if (!audioCtx) {
            audioCtx = new (window.AudioContext || window.webkitAudioContext)();
        }
        if (audioCtx.state === 'suspended') {
            audioCtx.resume();
        }
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.type = 'sine';
        osc.frequency.setValueAtTime(587.33, audioCtx.currentTime); // D5
        osc.frequency.exponentialRampToValueAtTime(880, audioCtx.currentTime + 0.12); // A5
        gain.gain.setValueAtTime(0.12, audioCtx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, audioCtx.currentTime + 0.25);
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start();
        osc.stop(audioCtx.currentTime + 0.25);
    } catch (e) {
        console.warn("Audio chime playback notice: ", e);
    }
}

// Toggle Audio Chime
function toggleAudioChime() {
    audioEnabled = !audioEnabled;
    const label = document.getElementById("sound-label");
    const icon = document.getElementById("sound-icon");
    if (label && icon) {
        label.innerText = audioEnabled ? "Sound On" : "Muted";
        icon.className = audioEnabled ? "fa-solid fa-volume-high text-violet-400" : "fa-solid fa-volume-xmark text-gray-500";
    }
}

// Reset web dashboard back to initial clean home state
function resetToHomeState() {
    if (otpInterval) clearInterval(otpInterval);
    otpInterval = null;
    currentToken = null;
    currentSessionId = null;
    enrolledStudentsCount = 0;

    if (unsubscribeAttendance) {
        unsubscribeAttendance();
        unsubscribeAttendance = null;
    }
    if (unsubscribeSession) {
        unsubscribeSession();
        unsubscribeSession = null;
    }

    const cleanUrl = window.location.protocol + "//" + window.location.host + window.location.pathname;
    window.history.pushState({ path: cleanUrl }, '', cleanUrl);

    if (sessionInput) sessionInput.value = "";
    if (classTitleEl) classTitleEl.innerText = "Classroom Projector";
    if (classCodeEl) classCodeEl.innerText = "Enter Session PIN to Connect";
    if (sessionBadgeEl) {
        sessionBadgeEl.className = "bg-violet-500/15 border border-violet-500/30 text-violet-300 text-xs font-bold px-3.5 py-1 rounded-full uppercase tracking-wider inline-block";
        sessionBadgeEl.innerText = "Waiting for Session";
    }
    if (sessionPinDisplayEl) sessionPinDisplayEl.innerText = "------";
    if (bleUuidEl) bleUuidEl.innerText = "Waiting for session...";
    if (laserBeamEl) laserBeamEl.style.display = "none";

    if (connectionStatusEl) {
        connectionStatusEl.className = "text-xs font-semibold text-gray-400 flex items-center gap-2 justify-end";
        connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-gray-500"></span> Disconnected`;
    }

    if (closeSessionBtn) closeSessionBtn.style.display = "none";

    if (qrcodeContainer) {
        qrcodeContainer.innerHTML = `
            <div class="text-center py-10 text-gray-400">
                <i class="fa-solid fa-qrcode text-6xl block mb-4 text-violet-400/40"></i>
                <span class="font-bold text-base block text-gray-300">Enter Class Session PIN to Project</span>
                <span class="text-xs text-gray-500 block mt-1">Session PIN is displayed on the teacher's phone app screen.</span>
            </div>
        `;
    }

    if (studentsGrid) studentsGrid.innerHTML = "";
    updateTurnoutGauge(0);
    showEmptyState();
}

// Manual connection trigger from input bar
if (loadBtn) {
    loadBtn.addEventListener("click", () => {
        const sessionId = sessionInput.value.trim();
        if (sessionId) {
            const newurl = window.location.protocol + "//" + window.location.host + window.location.pathname + `?session_id=${sessionId}`;
            window.history.pushState({path:newurl}, '', newurl);
            connectToSession(sessionId, false);
        } else {
            alert("Please enter a valid 6-Digit Session PIN or Document ID.");
        }
    });
}

// Handle termination of active session
function handleSessionEnded() {
    if (otpInterval) clearInterval(otpInterval);
    otpInterval = null;
    currentToken = null;
    
    const cleanUrl = window.location.protocol + "//" + window.location.host + window.location.pathname;
    window.history.pushState({ path: cleanUrl }, '', cleanUrl);
    if (sessionInput) sessionInput.value = "";

    if (classCodeEl) classCodeEl.innerText = "Session Completed";
    if (sessionBadgeEl) {
        sessionBadgeEl.className = "bg-rose-500/15 border border-rose-500/30 text-rose-400 text-xs font-bold px-3.5 py-1 rounded-full uppercase tracking-wider inline-block";
        sessionBadgeEl.innerText = "Attendance Closed";
    }
    if (connectionStatusEl) {
        connectionStatusEl.className = "text-xs font-semibold text-rose-400 flex items-center gap-2 justify-end";
        connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Session Closed`;
    }
    
    if (closeSessionBtn) closeSessionBtn.style.display = "none";
    if (laserBeamEl) laserBeamEl.style.display = "none";
    
    if (qrcodeContainer) {
        qrcodeContainer.innerHTML = `
            <div class="text-rose-400 text-center py-10">
                <i class="fa-solid fa-circle-check text-5xl block mb-3 text-emerald-400"></i>
                <span class="font-extrabold text-lg block text-white">Attendance Closed</span>
                <span class="text-xs text-gray-400 block mt-1">The teacher has concluded this attendance session.</span>
            </div>
        `;
    }
}

// Update Turnout Progress Bar & Ratio
function updateTurnoutGauge(presentCount) {
    if (presentRatioEl) {
        if (enrolledStudentsCount > 0) {
            const pct = Math.round((presentCount / enrolledStudentsCount) * 100);
            presentRatioEl.innerText = `${presentCount} / ${enrolledStudentsCount} Present (${pct}%)`;
            if (turnoutBarEl) turnoutBarEl.style.width = `${Math.min(100, pct)}%`;
        } else {
            presentRatioEl.innerText = `${presentCount} Present`;
            if (turnoutBarEl) turnoutBarEl.style.width = `100%`;
        }
    }
}

// Connect to Firestore Session and set up real-time listener
async function connectToSession(sessionId, isAutoConnect = false) {
    if (otpInterval) clearInterval(otpInterval);
    if (unsubscribeAttendance) unsubscribeAttendance();
    if (unsubscribeSession) unsubscribeSession();
    
    connectionStatusEl.className = "text-xs font-semibold text-amber-400 flex items-center gap-2 justify-end";
    connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-amber-400 animate-ping"></span> Connecting...`;
    
    if (studentsGrid) studentsGrid.innerHTML = "";
    updateTurnoutGauge(0);
    showEmptyState();
    
    try {
        let docId = sessionId.toString().trim();
        
        // Fast resolution for 6-character short PIN or numeric PIN without requiring composite Firestore index
        if (docId.length === 6 || !isNaN(docId)) {
            connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-amber-400 animate-ping"></span> Finding PIN...`;
            
            // Single field query (no composite index required)
            let querySnapshot = await Promise.race([
                db.collection("sessions").where("short_id", "==", docId).limit(1).get(),
                new Promise((_, reject) => setTimeout(() => reject(new Error("Connection timeout")), 4000))
            ]).catch(() => null);

            // Fallback for numeric PIN type
            if ((!querySnapshot || querySnapshot.empty) && !isNaN(docId)) {
                querySnapshot = await db.collection("sessions")
                    .where("short_id", "==", parseInt(docId))
                    .limit(1)
                    .get()
                    .catch(() => null);
            }

            if (!querySnapshot || querySnapshot.empty) {
                // Try direct doc ID match as final fallback
                const directDoc = await db.collection("sessions").doc(docId).get().catch(() => null);
                if (directDoc && directDoc.exists) {
                    docId = directDoc.id;
                } else {
                    if (!isAutoConnect) {
                        alert("No session found matching Session PIN: " + sessionId);
                    }
                    resetToHomeState();
                    return;
                }
            } else {
                docId = querySnapshot.docs[0].id;
            }
        }

        currentSessionId = docId;

        // Start listening to the attendance collection for this session ID
        if (!unsubscribeAttendance) {
            unsubscribeAttendance = db.collection("attendance")
                .where("session_id", "==", docId)
                .onSnapshot((snapshot) => {
                    if (!snapshot || snapshot.empty) {
                        updateTurnoutGauge(0);
                        showEmptyState();
                    } else {
                        hideEmptyState();
                        updateTurnoutGauge(snapshot.docs.length);

                        // In-memory sort by timestamp ascending
                        const docs = snapshot.docs.sort((a, b) => {
                            const tA = a.data().timestamp ? (a.data().timestamp.seconds || 0) : 0;
                            const tB = b.data().timestamp ? (b.data().timestamp.seconds || 0) : 0;
                            return tA - tB;
                        });

                        docs.forEach((doc) => {
                            const checkin = doc.data();
                            let timeStr = "";
                            if (checkin.timestamp && checkin.timestamp.toDate) {
                                const date = checkin.timestamp.toDate();
                                timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
                            } else {
                                timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
                            }

                            addStudentToGrid({
                                student_id: checkin.student_id || doc.id,
                                student_name: checkin.student_name || checkin.name || 'Student',
                                student_username: checkin.student_username || checkin.username || 'Verified',
                                time_str: timeStr,
                                verified_face: checkin.verified_face !== false,
                                verified_proximity: checkin.verified_proximity !== false,
                            });
                        });
                    }
                }, (err) => {
                    console.error("Firestore attendance listening error: ", err);
                });
        }

        // Start listening to the Session Document in real time
        unsubscribeSession = db.collection("sessions").doc(docId)
            .onSnapshot(async (sessionDoc) => {
                if (!sessionDoc.exists) {
                    if (isAutoConnect) {
                        resetToHomeState();
                    } else {
                        handleSessionEnded();
                    }
                    return;
                }
                
                const sessionData = sessionDoc.data();
                
                // Render class info
                classTitleEl.innerText = sessionData.class_name || "Class Session";
                bleUuidEl.innerText = sessionData.ble_uuid || "Waiting for signal...";
                
                if (sessionPinDisplayEl) {
                    sessionPinDisplayEl.innerText = sessionData.short_id || "------";
                }

                // Fetch total enrolled student count for class if available
                if (sessionData.class_id) {
                    try {
                        const classDoc = await db.collection("classes").doc(sessionData.class_id).get();
                        if (classDoc.exists && classDoc.data().student_ids) {
                            enrolledStudentsCount = classDoc.data().student_ids.length;
                            // Re-update gauge with enrolled count
                            const count = parseInt(presentRatioEl.innerText) || 0;
                            updateTurnoutGauge(count);
                        }
                    } catch (e) {
                        console.log("Class enrolled count lookup: ", e);
                    }
                }

                if (!sessionData.is_active) {
                    if (isAutoConnect) {
                        resetToHomeState();
                    } else {
                        handleSessionEnded();
                    }
                    return;
                }

                classCodeEl.innerText = "Session Active";
                if (sessionBadgeEl) {
                    sessionBadgeEl.className = "bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 text-xs font-bold px-3.5 py-1 rounded-full uppercase tracking-wider inline-block";
                    sessionBadgeEl.innerText = "Active Attendance Session";
                }

                if (closeSessionBtn) closeSessionBtn.style.display = "flex";
                if (laserBeamEl) laserBeamEl.style.display = "block";

                let startTime = null;
                if (sessionData.start_time) {
                    startTime = sessionData.start_time.toDate();
                }

                // Initialize client-side TOTP loop if not already started
                if (!otpInterval) {
                    connectionStatusEl.className = "text-xs font-semibold text-emerald-400 flex items-center gap-2 justify-end";
                    connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-emerald-400"></span> Connected to Cloud`;
                    
                    const totp = new OTPAuth.TOTP({
                        secret: OTPAuth.Secret.fromBase32(sessionData.otp_secret),
                        period: 10,
                        digits: 6
                    });

                    otpInterval = setInterval(() => {
                        const nowSeconds = Math.floor(Date.now() / 1000);
                        const expiresIn = 10 - (nowSeconds % 10);
                        const token = totp.generate();
                        
                        if (currentToken !== token) {
                            currentToken = token;
                            renderQRCode(token);
                        }
                        
                        updateCountdown(expiresIn);

                        // Check 3-minute auto-termination countdown
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
            }, (err) => {
                console.error("Session snapshot error:", err);
                connectionStatusEl.className = "text-xs font-semibold text-rose-400 flex items-center gap-2 justify-end";
                connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Connection Error`;
            });

    } catch (e) {
        console.error("Failed to load session details: ", e);
        connectionStatusEl.className = "text-xs font-semibold text-rose-400 flex items-center gap-2 justify-end";
        connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500"></span> Connection Error`;
    }
}

// Render dynamic QR code containing session data
function renderQRCode(token) {
    qrcodeContainer.innerHTML = "";
    
    const payload = JSON.stringify({
        session_id: currentSessionId,
        token: token
    });
    
    new QRCode(qrcodeContainer, {
        text: payload,
        width: 240,
        height: 240,
        colorDark : "#09070f",
        colorLight : "#ffffff",
        correctLevel : QRCode.CorrectLevel.H
    });
}

// Update countdown timer and bar
function updateCountdown(expiresIn) {
    expiryTimerEl.innerText = `Refreshing in ${expiresIn}s`;
    
    const percentage = (expiresIn / 10) * 100;
    expiryBarEl.style.width = `${percentage}%`;
    
    if (expiresIn <= 3) {
        expiryBarEl.className = "bg-gradient-to-r from-rose-500 to-red-500 h-full w-full transition-all duration-1000 ease-linear";
        expiryTimerEl.className = "text-rose-400 font-bold animate-pulse";
    } else {
        expiryBarEl.className = "bg-gradient-to-r from-violet-500 to-emerald-400 h-full w-full transition-all duration-1000 ease-linear";
        expiryTimerEl.className = "text-violet-400 font-bold";
    }
}

// Append checked-in student card to grid cleanly
function addStudentToGrid(student) {
    const cardId = `student-${student.student_id}`;
    const existingCard = document.getElementById(cardId);
    if (existingCard) return;

    // Safely extract student name & username
    const rawName = (student.student_name || student.name || 'Student').toString().trim();
    const rawUname = (student.student_username || student.username || student.student_id || 'ID').toString().trim();
    
    const parts = rawName.split(/\s+/);
    const initials = (parts.length > 1 ? (parts[0][0] + parts[parts.length - 1][0]) : (parts[0][0] || 'S')).toUpperCase();

    const card = document.createElement("div");
    card.id = cardId;
    card.className = "student-card glass-panel rounded-2xl p-3.5 flex items-center gap-3";
    
    card.innerHTML = `
        <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-violet-500/25 to-indigo-500/25 border border-violet-500/40 flex items-center justify-center text-xs font-extrabold text-violet-300 shrink-0">
            ${initials}
        </div>
        <div class="min-w-0 flex-grow">
            <h4 class="font-extrabold text-sm text-white truncate">${rawName}</h4>
            <div class="flex justify-between items-center mt-1">
                <span class="text-[10px] text-gray-400 font-mono font-medium truncate mr-2">${rawUname}</span>
                <span class="text-[10px] text-emerald-400 font-bold bg-emerald-500/10 border border-emerald-500/20 px-1.5 py-0.5 rounded flex items-center gap-1 font-mono shrink-0">
                    <i class="fa-solid fa-clock text-[8px]"></i> ${student.time_str}
                </span>
            </div>
            <div class="flex gap-1 mt-1.5">
                <span class="text-[8px] font-bold text-emerald-300 bg-emerald-500/15 border border-emerald-500/30 px-1 rounded">Face ID ✓</span>
                <span class="text-[8px] font-bold text-violet-300 bg-violet-500/15 border border-violet-500/30 px-1 rounded">BLE ✓</span>
                <span class="text-[8px] font-bold text-indigo-300 bg-indigo-500/15 border border-indigo-500/30 px-1 rounded">TOTP ✓</span>
            </div>
        </div>
    `;
    
    studentsGrid.appendChild(card);
    playCheckinChime();
}

// Show/hide helper functions
function showEmptyState() {
    if (emptyStateEl) emptyStateEl.style.display = "flex";
}

function hideEmptyState() {
    if (emptyStateEl) emptyStateEl.style.display = "none";
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

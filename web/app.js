// Global state
let socket = null;
let qrcode = null;
let currentToken = null;
let currentSessionId = null;

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

// Initialize page
window.addEventListener("DOMContentLoaded", () => {
    // Check if session_id is in URL query parameters (e.g., ?session_id=1)
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
        alert("Please enter a valid Session ID.");
    }
});

// Connect to WebSocket Server
function connectToSession(sessionId) {
    // If active connection exists, close it
    if (socket) {
        socket.close();
    }
    
    currentSessionId = sessionId;
    
    // Set status to connecting
    connectionStatusEl.className = "text-sm font-semibold text-amber-500 flex items-center gap-2 justify-end";
    connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-amber-500 animate-pulse"></span> Connecting...`;
    
    // Clear student grid and count
    studentsGrid.innerHTML = "";
    presentCountEl.innerText = "0";
    showEmptyState();
    
    // Determine WS protocol based on page protocol
    const wsProtocol = window.location.protocol === "https:" ? "wss:" : "ws:";
    const host = window.location.host || "localhost:8000";
    
    // Establish connection to backend WebSocket
    const wsUrl = `${wsProtocol}//${host}/ws/class/${sessionId}`;
    socket = new WebSocket(wsUrl);
    
    socket.onopen = () => {
        console.log(`Connected to session WebSocket: ${sessionId}`);
        connectionStatusEl.className = "text-sm font-semibold text-emerald-500 flex items-center gap-2 justify-end";
        connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-emerald-500"></span> Connected`;
    };
    
    socket.onmessage = (event) => {
        const data = JSON.parse(event.data);
        handleWebSocketMessage(data);
    };
    
    socket.onclose = () => {
        console.log("WebSocket connection closed.");
        connectionStatusEl.className = "text-sm font-semibold text-rose-500 flex items-center gap-2 justify-end";
        connectionStatusEl.innerHTML = `<span class="w-2.5 h-2.5 rounded-full bg-rose-500 animate-pulse"></span> Disconnected`;
        // Clear QR code to prevent scans on disconnected system
        qrcodeContainer.innerHTML = `<div class="text-rose-400 text-center"><i class="fa-solid fa-triangle-exclamation text-4xl block mb-2"></i> Connection Lost</div>`;
    };
    
    socket.onerror = (err) => {
        console.error("WebSocket encountered an error:", err);
    };
}

// Handle messages from FastAPI server
function handleWebSocketMessage(data) {
    if (data.error) {
        alert(data.error);
        showEmptyState();
        return;
    }
    
    switch (data.type) {
        case "init":
            // Render class info
            classTitleEl.innerText = data.class_name;
            classCodeEl.innerText = data.class_code;
            bleUuidEl.innerText = data.ble_uuid;
            
            // Render any existing checkins
            if (data.checkins && data.checkins.length > 0) {
                hideEmptyState();
                data.checkins.forEach(student => addStudentToGrid(student));
            }
            break;
            
        case "otp_update":
            // Draw QR code if token has changed
            if (currentToken !== data.token) {
                currentToken = data.token;
                renderQRCode(data.token);
            }
            
            // Update expiring progress bar UI
            updateCountdown(data.expires_in);
            break;
            
        case "student_checkin":
            hideEmptyState();
            addStudentToGrid(data);
            break;
            
        default:
            console.warn("Unknown socket action type:", data.type);
    }
}

// Render dynamic QR code containing session data
function renderQRCode(token) {
    qrcodeContainer.innerHTML = ""; // Clear loader/previous QR
    
    // Payload scanned by student contains the session ID and OTP token
    const payload = JSON.stringify({
        session_id: parseInt(currentSessionId),
        token: token
    });
    
    // Create new QR Code using the qrcode.js CDN library
    qrcode = new QRCode(qrcodeContainer, {
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
    // Update label
    expiryTimerEl.innerText = `Refreshing in ${expiresIn}s`;
    
    // Update progress bar percentage (10 seconds total)
    const percentage = (expiresIn / 10) * 100;
    expiryBarEl.style.width = `${percentage}%`;
    
    // Change color as it gets close to expiring
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
    // Check if student already in grid
    const existingCard = document.getElementById(`student-${student.student_id}`);
    if (existingCard) return;

    // Increment count
    const currentCount = parseInt(presentCountEl.innerText);
    presentCountEl.innerText = currentCount + 1;
    
    // Extract formatted time
    let timeStr = "";
    if (student.timestamp) {
        const date = new Date(student.timestamp);
        timeStr = date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } else {
        timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    }

    // Create student card markup
    const card = document.createElement("div");
    card.id = `student-${student.student_id}`;
    card.className = "student-card glass-panel rounded-2xl p-4 flex items-center gap-3";
    
    // Get unique initials or avatar
    const initials = student.student_name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2);
    
    card.innerHTML = `
        <div class="w-10 h-10 rounded-xl bg-gradient-to-tr from-violet-500/20 to-indigo-500/20 border border-violet-500/30 flex items-center justify-center text-sm font-bold text-violet-300">
            ${initials}
        </div>
        <div class="min-w-0 flex-grow">
            <h4 class="font-bold text-sm text-white truncate">${student.student_name}</h4>
            <div class="flex justify-between items-center mt-0.5">
                <span class="text-[10px] text-gray-500 font-medium font-mono">${student.student_username}</span>
                <span class="text-[10px] text-emerald-400 font-semibold bg-emerald-500/10 px-1.5 py-0.5 rounded flex items-center gap-1 font-mono">
                    <i class="fa-solid fa-clock text-[8px]"></i> ${timeStr}
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

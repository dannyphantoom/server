function sendMessage() {
    const input = document.getElementById('message-input');
    const message = input.value.trim();
    if (!message) return;

    fetch('/message', {
        method: 'POST',
        headers: { 'Content-Type': 'text/plain' },
        body: message
    }).then(() => {
        animateMessage(message);
        input.value = '';
    }).catch(err => {
        console.error(err);
    });
}

function animateMessage(text) {
    const msgDiv = document.createElement('div');
    msgDiv.className = 'sent-message';
    msgDiv.textContent = text;
    document.body.appendChild(msgDiv);
    msgDiv.addEventListener('animationend', () => msgDiv.remove());
}

/* =============================================================================
   MoaV Landing Page - Script
   ============================================================================= */

document.addEventListener('DOMContentLoaded', () => {
    initNetworkBackground();
    initCopyButtons();
    initCryptoButtons();
    initTypingAnimation();
    initDemoVideos();
    initDemoModal();
});

/* =============================================================================
   Network Background Animation
   Subtle floating particles with random connections
   ============================================================================= */

function initNetworkBackground() {
    const canvas = document.getElementById('network-bg');
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    let particles = [];
    let animationId;

    // Configuration
    const config = {
        particleCount: 60,
        particleSize: 2,
        connectionDistance: 150,
        speed: 0.3,
        colors: {
            particle: 'rgba(0, 212, 255, 0.6)',
            connection: 'rgba(0, 212, 255, 0.1)',
            particleAlt: 'rgba(123, 92, 255, 0.4)'
        }
    };

    // Particle class
    class Particle {
        constructor() {
            this.reset();
        }

        reset() {
            this.x = Math.random() * canvas.width;
            this.y = Math.random() * canvas.height;

            // Random velocity with some randomness to direction changes
            this.vx = (Math.random() - 0.5) * config.speed;
            this.vy = (Math.random() - 0.5) * config.speed;

            // Random acceleration for organic movement
            this.ax = 0;
            this.ay = 0;

            // Time until next direction change
            this.changeTime = Math.random() * 200 + 100;
            this.timer = 0;

            // Size variation
            this.size = config.particleSize * (0.5 + Math.random() * 0.5);

            // Color variation
            this.isAlt = Math.random() > 0.7;
        }

        update() {
            this.timer++;

            // Randomly change direction for organic movement
            if (this.timer > this.changeTime) {
                this.timer = 0;
                this.changeTime = Math.random() * 200 + 100;

                // Add small random acceleration
                this.ax = (Math.random() - 0.5) * 0.02;
                this.ay = (Math.random() - 0.5) * 0.02;
            }

            // Apply acceleration
            this.vx += this.ax;
            this.vy += this.ay;

            // Limit velocity
            const maxSpeed = config.speed * 1.5;
            const speed = Math.sqrt(this.vx * this.vx + this.vy * this.vy);
            if (speed > maxSpeed) {
                this.vx = (this.vx / speed) * maxSpeed;
                this.vy = (this.vy / speed) * maxSpeed;
            }

            // Apply velocity
            this.x += this.vx;
            this.y += this.vy;

            // Wrap around edges
            if (this.x < 0) this.x = canvas.width;
            if (this.x > canvas.width) this.x = 0;
            if (this.y < 0) this.y = canvas.height;
            if (this.y > canvas.height) this.y = 0;
        }

        draw() {
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = this.isAlt ? config.colors.particleAlt : config.colors.particle;
            ctx.fill();
        }
    }

    // Initialize
    function init() {
        resize();
        particles = [];
        for (let i = 0; i < config.particleCount; i++) {
            particles.push(new Particle());
        }
    }

    // Resize handler
    function resize() {
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
    }

    // Draw connections between nearby particles
    function drawConnections() {
        for (let i = 0; i < particles.length; i++) {
            for (let j = i + 1; j < particles.length; j++) {
                const dx = particles[i].x - particles[j].x;
                const dy = particles[i].y - particles[j].y;
                const distance = Math.sqrt(dx * dx + dy * dy);

                if (distance < config.connectionDistance) {
                    const opacity = 1 - (distance / config.connectionDistance);
                    ctx.beginPath();
                    ctx.moveTo(particles[i].x, particles[i].y);
                    ctx.lineTo(particles[j].x, particles[j].y);
                    ctx.strokeStyle = `rgba(0, 212, 255, ${opacity * 0.15})`;
                    ctx.lineWidth = 1;
                    ctx.stroke();
                }
            }
        }
    }

    // Animation loop
    function animate() {
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // Update and draw particles
        particles.forEach(particle => {
            particle.update();
            particle.draw();
        });

        // Draw connections
        drawConnections();

        animationId = requestAnimationFrame(animate);
    }

    // Event listeners
    window.addEventListener('resize', () => {
        resize();
    });

    // Reduce animation on low-power mode or preference
    const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    if (prefersReducedMotion.matches) {
        config.speed = 0.1;
        config.particleCount = 30;
    }

    // Start
    init();
    animate();

    // Cleanup on page hide
    document.addEventListener('visibilitychange', () => {
        if (document.hidden) {
            cancelAnimationFrame(animationId);
        } else {
            animate();
        }
    });
}

/* =============================================================================
   Copy to Clipboard
   ============================================================================= */

function initCopyButtons() {
    const copyButtons = document.querySelectorAll('.copy-btn');

    copyButtons.forEach(button => {
        button.addEventListener('click', async () => {
            const targetId = button.dataset.target;
            const targetElement = document.getElementById(targetId);

            if (!targetElement) return;

            const text = targetElement.textContent.trim();

            try {
                await navigator.clipboard.writeText(text);

                // Visual feedback
                button.classList.add('copied');
                const originalContent = button.innerHTML;

                if (button.textContent.trim() === 'Copy') {
                    button.textContent = 'Copied!';
                } else {
                    button.innerHTML = `
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <polyline points="20 6 9 17 4 12"></polyline>
                        </svg>
                    `;
                }

                setTimeout(() => {
                    button.classList.remove('copied');
                    button.innerHTML = originalContent;
                }, 2000);
            } catch (err) {
                console.error('Failed to copy:', err);
            }
        });
    });
}

/* =============================================================================
   Crypto Donation Buttons - Copy on Click
   ============================================================================= */

function initCryptoButtons() {
    const cryptoButtons = document.querySelectorAll('.crypto-btn');

    cryptoButtons.forEach(button => {
        button.addEventListener('click', async () => {
            const address = button.dataset.address;

            if (!address) return;

            try {
                await navigator.clipboard.writeText(address);

                // Visual feedback
                button.classList.add('copied');

                setTimeout(() => {
                    button.classList.remove('copied');
                }, 2000);
            } catch (err) {
                console.error('Failed to copy:', err);
            }
        });
    });
}

/* =============================================================================
   Typing Animation for Terminal
   ============================================================================= */

function initTypingAnimation() {
    const commandElement = document.getElementById('install-cmd');
    if (!commandElement) return;

    const fullText = commandElement.textContent;
    const typingSpeed = 50; // ms per character
    const startDelay = 1000; // Wait before starting

    // Clear and prepare for animation
    commandElement.textContent = '';
    commandElement.classList.add('typing-cursor');

    let charIndex = 0;

    function type() {
        if (charIndex < fullText.length) {
            commandElement.textContent += fullText.charAt(charIndex);
            charIndex++;
            setTimeout(type, typingSpeed + Math.random() * 30); // Add slight randomness
        } else {
            // Remove cursor after typing complete
            setTimeout(() => {
                commandElement.classList.remove('typing-cursor');
            }, 500);
        }
    }

    // Start typing after delay
    setTimeout(type, startDelay);
}

/* =============================================================================
   Smooth Scroll (for any anchor links)
   ============================================================================= */

document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

/* =============================================================================
   Intersection Observer for fade-in animations
   ============================================================================= */

const observerOptions = {
    root: null,
    rootMargin: '0px',
    threshold: 0.1
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('visible');
            observer.unobserve(entry.target);
        }
    });
}, observerOptions);

// Observe sections for animations
document.querySelectorAll('section').forEach(section => {
    section.classList.add('fade-section');
    observer.observe(section);
});

// Add CSS for fade animation dynamically
const style = document.createElement('style');
style.textContent = `
    .fade-section {
        opacity: 0;
        transform: translateY(20px);
        transition: opacity 0.6s ease, transform 0.6s ease;
    }
    .fade-section.visible {
        opacity: 1;
        transform: translateY(0);
    }
`;
document.head.appendChild(style);

/* =============================================================================
   Demo Videos - Check if video exists and show/hide placeholder
   ============================================================================= */

function initDemoVideos() {
    const demoBoxes = document.querySelectorAll('.demo-box[data-demo]');

    demoBoxes.forEach(box => {
        const video = box.querySelector('.demo-video');
        const container = box.querySelector('.demo-video-container');

        if (!video || !container) return;

        // Check if video can be loaded
        video.addEventListener('loadeddata', () => {
            container.classList.add('video-loaded');
        });

        video.addEventListener('error', () => {
            // Video failed to load, placeholder will show
            container.classList.remove('video-loaded');
        });

        // Try to load the video
        video.load();
    });
}

/* =============================================================================
   Demo Modal - Lightbox for demo videos
   ============================================================================= */

function initDemoModal() {
    const modal = document.getElementById('demo-modal');
    if (!modal) return;

    const backdrop = modal.querySelector('.demo-modal-backdrop');
    const closeBtn = modal.querySelector('.demo-modal-close');
    const modalVideo = modal.querySelector('.demo-modal-video');
    const modalTitle = modal.querySelector('.demo-modal-title');

    // Demo titles mapping
    const demoTitles = {
        'install': 'Quick Installation',
        'setup': 'Setup & Bootstrap',
        'services': 'Service Management',
        'users': 'User Management',
        'server': 'Server Management'
    };

    // Open modal when clicking on demo box
    document.querySelectorAll('.demo-box[data-demo]').forEach(box => {
        box.addEventListener('click', () => {
            const demoName = box.dataset.demo;
            const video = box.querySelector('.demo-video');

            // Only open modal if video exists and loaded
            if (!video || !box.querySelector('.demo-video-container').classList.contains('video-loaded')) {
                return;
            }

            const videoSrc = video.querySelector('source')?.src || video.dataset.src;

            // Set modal content
            modalTitle.textContent = demoTitles[demoName] || demoName;
            modalVideo.querySelector('source').src = videoSrc;
            modalVideo.load();
            modalVideo.play();

            // Open modal
            modal.classList.add('active');
            document.body.classList.add('modal-open');
        });
    });

    // Close modal functions
    function closeModal() {
        modal.classList.remove('active');
        document.body.classList.remove('modal-open');
        modalVideo.pause();
        modalVideo.currentTime = 0;
    }

    // Close on backdrop click
    backdrop.addEventListener('click', closeModal);

    // Close on close button click
    closeBtn.addEventListener('click', closeModal);

    // Close on escape key
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && modal.classList.contains('active')) {
            closeModal();
        }
    });
}

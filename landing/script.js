/* ════════════════════════════════════════════════════════
   MEHD AI — Landing Page Logic
   Particles, Terminal, Scroll Reveals, Interactions
   ════════════════════════════════════════════════════════ */

document.addEventListener('DOMContentLoaded', () => {

    // ═══════════ INSANE BLUE FLAME SYSTEM ═══════════
    const canvas = document.getElementById('particle-canvas');
    const ctx = canvas.getContext('2d');
    let particles = [];
    let mouse = { x: -1000, y: -1000 };

    function resizeCanvas() {
        canvas.width = document.documentElement.clientWidth;
        canvas.height = window.innerHeight;
    }
    resizeCanvas();
    window.addEventListener('resize', resizeCanvas);

    document.addEventListener('mousemove', e => {
        mouse.x = e.clientX;
        mouse.y = e.clientY;
    });

    class FlameParticle {
        constructor() {
            this.reset(true);
        }
        reset(randomY = false) {
            this.x = Math.random() * canvas.width;
            this.y = randomY ? Math.random() * canvas.height : canvas.height + Math.random() * 100;
            this.size = Math.random() * 4 + 1;
            
            // Flames move up and slightly drift left/right
            this.speedY = -Math.random() * 2 - 0.5;
            this.speedX = (Math.random() - 0.5) * 1.5;
            
            // Start at bottom and fade out as it goes up
            this.life = Math.random() * 0.5 + 0.5; 
            
            // Blue/Cyan/Purple fire colors
            const r = Math.random();
            if (r < 0.5) this.color = '0, 209, 255';        // Cyan core
            else if (r < 0.8) this.color = '88, 166, 255';  // Blue edge
            else this.color = '189, 147, 249';              // Purple wisp
        }
        update() {
            this.x += this.speedX;
            this.y += this.speedY;
            
            // Shrink and fade as it rises
            this.size *= 0.99;
            this.life -= 0.005;

            // Subtle mouse attraction
            const dx = mouse.x - this.x;
            const dy = mouse.y - this.y;
            const dist = Math.sqrt(dx*dx + dy*dy);
            if (dist < 300) {
                this.x += dx * 0.002;
                this.y += dy * 0.002;
            }

            if (this.life <= 0 || this.size <= 0.2 || this.y < -50) {
                this.reset();
            }
        }
        draw() {
            const alpha = Math.max(0, this.life);
            
            // Glowing fire effect (screen blending)
            ctx.globalCompositeOperation = 'screen';
            
            // Outer glow
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size * 3, 0, Math.PI * 2);
            const gradient = ctx.createRadialGradient(this.x, this.y, 0, this.x, this.y, this.size * 3);
            gradient.addColorStop(0, `rgba(${this.color}, ${alpha * 0.4})`);
            gradient.addColorStop(1, `rgba(${this.color}, 0)`);
            ctx.fillStyle = gradient;
            ctx.fill();

            // Intense Core
            ctx.beginPath();
            ctx.arc(this.x, this.y, this.size, 0, Math.PI * 2);
            ctx.fillStyle = `rgba(255, 255, 255, ${alpha * 0.8})`;
            ctx.fill();
        }
    }

    // Drastically reduced particle count for elite performance
    const particleCount = window.innerWidth < 768 ? 20 : 50;
    for (let i = 0; i < particleCount; i++) {
        particles.push(new FlameParticle());
    }

    function animateParticles() {
        ctx.globalCompositeOperation = 'source-over';
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        
        particles.forEach(p => { p.update(); p.draw(); });
        
        requestAnimationFrame(animateParticles);
    }
    animateParticles();


    // ═══════════ NAV: Scroll ═══════════
    const nav = document.getElementById('main-nav');
    window.addEventListener('scroll', () => {
        nav.classList.toggle('nav--scrolled', window.scrollY > 60);
    }, { passive: true });

    // NAV: Mobile hamburger
    const hamburger = document.getElementById('nav-hamburger');
    const navLinks = document.getElementById('nav-links');
    hamburger?.addEventListener('click', () => navLinks.classList.toggle('nav__links--open'));
    document.querySelectorAll('.nav__link').forEach(l => l.addEventListener('click', () => navLinks.classList.remove('nav__links--open')));


    // ═══════════ SCROLL REVEAL ═══════════
    const revealObserver = new IntersectionObserver((entries) => {
        entries.forEach((entry, i) => {
            if (entry.isIntersecting) {
                const delay = parseInt(entry.target.dataset.delay || '0');
                setTimeout(() => entry.target.classList.add('visible'), delay);
            }
        });
    }, { threshold: 0.08, rootMargin: '0px 0px -30px 0px' });

    document.querySelectorAll('.animate-in').forEach(el => revealObserver.observe(el));


    // ═══════════ TERMINAL ANIMATION ═══════════
    const termBody = document.getElementById('terminal-body');
    const sequence = [
        { t:'<span class="t-prompt">DEN</span> Deploying 11-Agent Consensus Grid...', c:'t-system', d:800 },
        { t:'', c:'', d:200 },
        { t:'┌─ UNDERWORLD // Sentiment Layer ──────┐', c:'t-info', d:300 },
        { t:'│ ✓ PHANTOM   — Stealth Recon    ONLINE', c:'t-success', d:120 },
        { t:'│ ✓ ORACLE    — Pattern Vision   ONLINE', c:'t-success', d:120 },
        { t:'│ ✓ DON       — Deep Intel       ONLINE', c:'t-success', d:120 },
        { t:'└──────────────────────────────────────┘', c:'t-info', d:200 },
        { t:'', c:'', d:100 },
        { t:'┌─ THE EMPIRE // Strategy Layer ───────┐', c:'t-warn', d:300 },
        { t:'│ ✓ CAESAR    — Command Auth     ONLINE', c:'t-success', d:120 },
        { t:'│ ✓ SAGE      — Risk Wisdom      ONLINE', c:'t-success', d:120 },
        { t:'│ ✓ GUARDIAN  — Shield Protocol  ONLINE', c:'t-success', d:120 },
        { t:'└──────────────────────────────────────┘', c:'t-warn', d:200 },
        { t:'', c:'', d:100 },
        { t:'┌─ OLYMPUS // Quantitative Layer ──────┐', c:'t-info', d:300 },
        { t:'│ ✓ TITAN     — Backtest Engine  ONLINE', c:'t-success', d:120 },
        { t:'│ ✓ ATLAS     — Quant Analysis   ONLINE', c:'t-success', d:120 },
        { t:'│ ✓ FORGE     — Math Core        ONLINE', c:'t-success', d:120 },
        { t:'└──────────────────────────────────────┘', c:'t-info', d:200 },
        { t:'', c:'', d:100 },
        { t:'┌─ SUPREME // Override Layer ──────────┐', c:'t-system', d:300 },
        { t:'│ ✓ SENTINEL  — Paradox Detector ONLINE', c:'t-success', d:120 },
        { t:'│ ✓ VANGUARD  — Recon Protocol   ONLINE', c:'t-success', d:120 },
        { t:'└──────────────────────────────────────┘', c:'t-system', d:300 },
        { t:'', c:'', d:200 },
        { t:'<span class="t-prompt">DEN</span> All 11 agents reporting. Consensus grid armed.', c:'t-success', d:600 },
        { t:'', c:'', d:200 },
        { t:'<span class="t-prompt">DEN</span> Incoming signal: EUR/USD LONG', c:'t-info', d:600 },
        { t:'', c:'', d:200 },
        { t:'  PHANTOM  ━ BUY  87% ████████░░', c:'t-vote-buy', d:100 },
        { t:'  ORACLE   ━ BUY  92% █████████░', c:'t-vote-buy', d:100 },
        { t:'  DON      ━ SELL 64% ██████░░░░', c:'t-vote-sell', d:100 },
        { t:'  CAESAR   ━ BUY  78% ███████░░░', c:'t-vote-buy', d:100 },
        { t:'  SAGE     ━ HOLD 55% █████░░░░░', c:'t-vote-hold', d:100 },
        { t:'  GUARDIAN ━ BUY  81% ████████░░', c:'t-vote-buy', d:100 },
        { t:'  TITAN    ━ BUY  89% ████████░░', c:'t-vote-buy', d:100 },
        { t:'  ATLAS    ━ BUY  74% ███████░░░', c:'t-vote-buy', d:100 },
        { t:'  FORGE    ━ BUY  83% ████████░░', c:'t-vote-buy', d:100 },
        { t:'  SENTINEL ━ BUY  91% █████████░', c:'t-vote-buy', d:100 },
        { t:'  VANGUARD ━ BUY  86% ████████░░', c:'t-vote-buy', d:200 },
        { t:'', c:'', d:200 },
        { t:'  ═══════════════════════════════', c:'t-system', d:200 },
        { t:'  CONSENSUS: BUY  (9/11)  Conf: 87%', c:'t-result', d:300 },
        { t:'  RISK:      1.2% capital │ 0.02 lots', c:'t-success', d:200 },
        { t:'  SHIELD:    ✓ ALL CHECKS PASSED', c:'t-success', d:200 },
        { t:'  ═══════════════════════════════', c:'t-system', d:300 },
        { t:'', c:'', d:100 },
        { t:'  █ TRADE PROTECTED — Capital is a seed, not a sacrifice.', c:'t-result', d:0 },
    ];

    let seqIdx = 0;
    let terminalStarted = false;

    function typeTerminal() {
        if (seqIdx >= sequence.length) {
            setTimeout(() => {
                termBody.innerHTML = '';
                seqIdx = 0;
                setTimeout(typeTerminal, 1500);
            }, 6000);
            return;
        }
        const line = sequence[seqIdx];
        const el = document.createElement('div');
        el.className = `t-line ${line.c}`;
        el.innerHTML = line.t || '&nbsp;';
        termBody.appendChild(el);
        termBody.scrollTop = termBody.scrollHeight;
        seqIdx++;
        setTimeout(typeTerminal, line.d + 60);
    }

    // Start terminal when visible
    const termSection = document.getElementById('engine');
    const termObserver = new IntersectionObserver((entries) => {
        if (entries[0].isIntersecting && !terminalStarted) {
            terminalStarted = true;
            setTimeout(typeTerminal, 500);
        }
    }, { threshold: 0.2 });
    termObserver.observe(termSection);


    // ═══════════ FAQ ACCORDION ═══════════
    document.querySelectorAll('.faq__q').forEach(btn => {
        btn.addEventListener('click', () => {
            const item = btn.closest('.faq__item');
            const isOpen = item.classList.contains('faq__item--open');
            document.querySelectorAll('.faq__item--open').forEach(i => i.classList.remove('faq__item--open'));
            if (!isOpen) item.classList.add('faq__item--open');
        });
    });


    // ═══════════ VOTE BAR ANIMATION ═══════════
    const voteBars = document.querySelectorAll('.vote-bar__fill');
    const voteObserver = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const target = entry.target.style.width;
                entry.target.style.width = '0%';
                setTimeout(() => { entry.target.style.width = target; }, 300);
            }
        });
    }, { threshold: 0.3 });
    voteBars.forEach(bar => voteObserver.observe(bar));


    // ═══════════ SMOOTH SCROLL ═══════════
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', e => {
            const href = anchor.getAttribute('href');
            if (href === '#') return;
            e.preventDefault();
            const target = document.querySelector(href);
            if (target) {
                const offset = 80;
                window.scrollTo({ top: target.getBoundingClientRect().top + window.scrollY - offset, behavior: 'smooth' });
            }
        });
    });

    // ═══════════ VIBE TERMINAL ANIMATION (SLASH COMMANDS) ═══════════
    const typewriterInput = document.getElementById('typewriter-input');
    const typewriterOutput = document.getElementById('typewriter-output');
    
    if (typewriterInput && typewriterOutput) {
        const vibeCommands = [
            { cmd: "/gold --consensus", out: "The Den has reached an absolute consensus to BUY. The Shadow has detected massive whale accumulation behind the scenes. You are cleared to execute. Strike now." },
            { cmd: "/exposure", out: "Current active risk is 1.2% across 2 positions. Maximum daily threshold is 2.0%. Account health is pristine. Capital is protected." },
            { cmd: "/market --truth", out: "Retail brokers are widening spreads by 1.2 pips. Institutional tape shows zero friction. The matrix is bleeding retail traders here. Stay flat." }
        ];

        let vibeIdx = 0;
        let isVibeAnimating = false;

        function playVibeTerminal() {
            typewriterInput.textContent = "";
            typewriterOutput.style.opacity = 0;
            typewriterOutput.textContent = "";
            
            const currentObj = vibeCommands[vibeIdx];
            const cmdText = currentObj.cmd;
            let charIdx = 0;

            function typeCmd() {
                if (charIdx < cmdText.length) {
                    typewriterInput.textContent += cmdText.charAt(charIdx);
                    charIdx++;
                    setTimeout(typeCmd, Math.random() * 50 + 50); // Human-like typing
                } else {
                    // Command finished typing, hit "Enter"
                    setTimeout(() => {
                        typewriterOutput.textContent = currentObj.out;
                        typewriterOutput.style.opacity = 1;
                        
                        // Wait before next command
                        setTimeout(() => {
                            vibeIdx = (vibeIdx + 1) % vibeCommands.length;
                            playVibeTerminal();
                        }, 5000);
                    }, 400);
                }
            }
            typeCmd();
        }

        const vibeObserver = new IntersectionObserver((entries) => {
            if (entries[0].isIntersecting && !isVibeAnimating) {
                isVibeAnimating = true;
                setTimeout(playVibeTerminal, 500);
            }
        }, { threshold: 0.3 });
        
        vibeObserver.observe(document.getElementById('features'));
    }

    // ═══════════ INSTITUTIONAL WAR ROOM ═══════════
    const neuralCanvas = document.getElementById('neural-canvas');
    const radarCanvas = document.getElementById('radar-canvas');
    
    if (neuralCanvas && radarCanvas) {
        const ctxN = neuralCanvas.getContext('2d');
        const ctxR = radarCanvas.getContext('2d');
        
        let width = neuralCanvas.parentElement.clientWidth;
        let height = neuralCanvas.parentElement.clientHeight;
        
        neuralCanvas.width = width * window.devicePixelRatio;
        neuralCanvas.height = height * window.devicePixelRatio;
        ctxN.scale(window.devicePixelRatio, window.devicePixelRatio);
        
        radarCanvas.width = width * window.devicePixelRatio;
        radarCanvas.height = height * window.devicePixelRatio;
        ctxR.scale(window.devicePixelRatio, window.devicePixelRatio);

        let radarAngle = 0;
        let pulseTime = 0;

        function drawWarRoom() {
            // Neural Network
            ctxN.clearRect(0, 0, width, height);
            const cx = width / 2;
            const cy = height / 2;
            
            const nodes = [
                {x: 0, y: -130, label: 'VANGUARD'},
                {x: -90, y: -60, label: 'GUARDIAN'},
                {x: 90, y: -60, label: 'TITAN'},
                {x: -140, y: 60, label: 'ATLAS'},
                {x: 140, y: 60, label: 'FORGE'},
                {x: 0, y: -20, label: 'PHANTOM'},
                {x: -90, y: 170, label: 'ORACLE'},
                {x: 0, y: 150, label: 'CAESAR'},
                {x: 90, y: 170, label: 'SAGE'}
            ];

            const pulse = (Math.sin(pulseTime) + 1) / 2;
            
            // Draw lines
            ctxN.strokeStyle = `rgba(255, 59, 59, ${0.2 + pulse * 0.3})`;
            ctxN.lineWidth = 1.5;
            nodes.forEach(node => {
                ctxN.beginPath();
                ctxN.moveTo(cx, cy);
                ctxN.lineTo(cx + node.x, cy + node.y);
                ctxN.stroke();
            });

            // Draw nodes
            nodes.forEach(node => {
                const nx = cx + node.x;
                const ny = cy + node.y;
                ctxN.fillStyle = '#FF3B3B';
                ctxN.beginPath();
                ctxN.arc(nx, ny, 4, 0, Math.PI * 2);
                ctxN.fill();
                
                ctxN.fillStyle = 'rgba(255, 59, 59, 0.7)';
                ctxN.font = '9px "JetBrains Mono"';
                ctxN.textAlign = 'center';
                ctxN.fillText(node.label, nx, ny + 15);
            });

            // Radar
            ctxR.clearRect(0, 0, width, height);
            const radius = Math.min(width, height) * 0.35;
            
            // Base Circle
            ctxR.beginPath();
            ctxR.arc(cx, cy, radius, 0, Math.PI * 2);
            ctxR.fillStyle = '#FF3B3B';
            ctxR.fill();

            // Sweep
            const grad = ctxR.createConicGradient(radarAngle - Math.PI/2, cx, cy);
            grad.addColorStop(0, 'rgba(0,0,0,0)');
            grad.addColorStop(0.25, 'rgba(0,0,0,0.8)');
            grad.addColorStop(1, 'rgba(0,0,0,0)');
            
            ctxR.beginPath();
            ctxR.arc(cx, cy, radius, 0, Math.PI * 2);
            ctxR.fillStyle = grad;
            ctxR.fill();

            radarAngle += 0.05;
            pulseTime += 0.05;
            requestAnimationFrame(drawWarRoom);
        }

        drawWarRoom();

        // Typewriter effect
        const textToType = `THE DON HAS INITIATED ANALYSIS...\n\nTHE UNDERWORLD: Gathering street intelligence and sentiment.\nTHE EMPIRE: Formulating imperial strategy and risk protocols.\nOLYMPUS: Calculating quantitative probabilities.\n\nAwaiting The Don's Synthesis...`;
        const decryptElement = document.getElementById('live-decrypt-text');
        
        const warRoomObserver = new IntersectionObserver((entries) => {
            if (entries[0].isIntersecting) {
                decryptElement.textContent = '';
                let i = 0;
                function typeChar() {
                    if (i < textToType.length) {
                        decryptElement.textContent += textToType.charAt(i);
                        i++;
                        setTimeout(typeChar, 30);
                    }
                }
                setTimeout(typeChar, 500);
                warRoomObserver.disconnect();
            }
        }, { threshold: 0.3 });
        
        warRoomObserver.observe(neuralCanvas);
    }

});

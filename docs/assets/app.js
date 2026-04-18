/* ============================================================
   KILL THE BILL — Documentation Viewer
   Reads the .md files directly. Hash-routed SPA.
   ============================================================ */

// ---------- Document tree (single source of nav truth) ----------

const DOCS = [
    { title: 'Vision', dir: '01-vision', icon: '■',
        intro: 'What the game IS before you ask how it is built.',
        pages: [
            { file: 'pitch.md',   title: 'Pitch' },
            { file: 'pillars.md', title: 'Pillars' },
            { file: 'tone.md',    title: 'Tone' },
        ]
    },
    { title: 'World', dir: '02-world', icon: '◆',
        intro: 'The simulation the player lives inside.',
        pages: [
            { file: 'regions.md',          title: 'Regions' },
            { file: 'landscapes.md',       title: 'Landscapes' },
            { file: 'economy.md',          title: 'Economy' },
            { file: 'senate.md',           title: 'The Senate' },
            { file: 'netfeed.md',          title: 'NetFeed' },
            { file: 'butterfly-effect.md', title: 'Butterfly Effect' },
        ]
    },
    { title: 'Characters', dir: '03-characters', icon: '●',
        intro: 'Billionaires, politicians, citizens, and the occasional myth.',
        pages: [
            { file: 'oligarchs.md',        title: 'Oligarchs' },
            { file: 'oligarch-web.md',     title: 'Oligarch Web' },
            { file: 'politicians.md',      title: 'Politicians' },
            { file: 'npcs.md',             title: 'NPCs' },
            { file: 'relationships.md',    title: 'Relationships' },
            { file: 'cultural-cameos.md',  title: 'Cultural Cameos' },
        ]
    },
    { title: 'Player', dir: '04-player', icon: '◉',
        intro: 'The loop the human drives.',
        pages: [
            { file: 'loop.md',        title: 'Core Loop' },
            { file: 'progression.md', title: 'Progression', stub: true },
            { file: 'combat.md',      title: 'Combat',      stub: true },
            { file: 'heat.md',        title: 'Heat & Evasion', stub: true },
            { file: 'victory.md',     title: 'Victory',     stub: true },
        ]
    },
    { title: 'Systems', dir: '05-systems', icon: '▲',
        intro: 'The tech underneath.',
        pages: [
            { file: 'save-and-share.md', title: 'Save & Share' },
            { file: 'architecture.md',   title: 'Architecture', stub: true },
            { file: 'llm.md',            title: 'LLM Stack',    stub: true },
            { file: 'ui.md',             title: 'UI',           stub: true },
            { file: 'visuals.md',        title: 'Visuals',      stub: true },
        ]
    },
    { title: 'Roadmap', dir: '06-roadmap', icon: '▼',
        intro: 'Where we are, where we are going.',
        pages: [
            { file: 'status.md', title: 'Status', stub: true },
            { file: 'phases.md', title: 'Phases', stub: true },
        ]
    },
];

// NetFeed-style flavor headlines scrolling in the header
const TICKER_HEADLINES = [
    "Public tension climbing in the Sinks. Enforcer deployment up 14%.",
    "Unverified broadcast on Pirate 88.8 calls for 'space monkeys'.",
    "Senate alignment shifts −7 after late-night Enclave gathering.",
    "Food price up 22% this cycle. Riots reported in Ash Row.",
    "Oligarch Vextol announces 'urban renewal' of Gray Depths.",
    "Six Workers reported missing after rally. Families silent.",
    "Compliance Post 14 reports 'no anomalous activity'. Locals disagree.",
    "Media spire broadcast: 'Everything is fine. Everything is fine.'",
    "Paper Street soap shipment intercepted. Chemistry flagged.",
    "Anonymous manifesto distributed in Substrate Fields. 47 pages.",
    "Heat tier raised to 3 in Obsidian Cay after unlicensed boat.",
    "NetFeed anomaly: identical headline reported across 8 outlets.",
];

// ---------- Lightweight Markdown renderer ----------
// Small, good-enough for this project. Handles:
//   headings, paragraphs, code fences, inline code, bold/em,
//   links, images, lists, tables, blockquotes, hr.

function mdEscape(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
function mdEscapeAttr(s) {
    return s.replace(/"/g, '&quot;');
}

function renderInline(s) {
    // Preserve inline code first (so ** etc. inside code doesn't expand)
    const codes = [];
    s = s.replace(/`([^`]+)`/g, (_, c) => {
        codes.push(mdEscape(c));
        return `\x01${codes.length - 1}\x01`;
    });
    s = mdEscape(s);
    // Images ![alt](src)
    s = s.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, (_, alt, src) =>
        `<img src="${mdEscapeAttr(src)}" alt="${mdEscapeAttr(alt)}">`);
    // Links [text](url)
    s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, text, url) =>
        `<a href="${mdEscapeAttr(url)}">${text}</a>`);
    // Bold, italic, strikethrough
    s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    s = s.replace(/(^|[^*])\*([^*\n]+)\*/g, '$1<em>$2</em>');
    s = s.replace(/~~([^~]+)~~/g, '<del>$1</del>');
    // Restore inline code
    s = s.replace(/\x01(\d+)\x01/g, (_, i) => `<code>${codes[+i]}</code>`);
    return s;
}

function renderMarkdown(src) {
    const lines = src.replace(/\r\n/g, '\n').split('\n');
    let out = '';
    let i = 0;

    function flushParagraph(buf) {
        const text = buf.join(' ').trim();
        if (text) out += `<p>${renderInline(text)}</p>\n`;
    }

    while (i < lines.length) {
        const line = lines[i];

        // Code fence
        if (/^```/.test(line)) {
            const lang = line.replace(/^```/, '').trim();
            let code = '';
            i++;
            while (i < lines.length && !/^```/.test(lines[i])) {
                code += lines[i] + '\n';
                i++;
            }
            i++;
            out += `<pre><code class="lang-${mdEscapeAttr(lang)}">${highlightCode(code.replace(/\n$/, ''), lang)}</code></pre>\n`;
            continue;
        }

        // Heading
        const h = line.match(/^(#{1,6})\s+(.*)$/);
        if (h) {
            const level = h[1].length;
            const text = h[2].trim();
            const id = slug(text);
            out += `<h${level} id="${id}">${renderInline(text)}</h${level}>\n`;
            i++;
            continue;
        }

        // Horizontal rule
        if (/^---+\s*$/.test(line) || /^\*\*\*+\s*$/.test(line)) {
            out += '<hr>\n';
            i++;
            continue;
        }

        // Blockquote
        if (/^>\s?/.test(line)) {
            let block = '';
            while (i < lines.length && /^>\s?/.test(lines[i])) {
                block += lines[i].replace(/^>\s?/, '') + '\n';
                i++;
            }
            out += `<blockquote>${renderMarkdown(block)}</blockquote>\n`;
            continue;
        }

        // Table — look for a header row followed by a separator row
        if (/^\s*\|/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-+/.test(lines[i + 1])) {
            const rows = [];
            while (i < lines.length && /^\s*\|/.test(lines[i])) {
                rows.push(lines[i]);
                i++;
            }
            if (rows.length >= 2) {
                const header = splitRow(rows[0]);
                const body = rows.slice(2).map(splitRow);
                out += '<table><thead><tr>';
                for (const h of header) out += `<th>${renderInline(h)}</th>`;
                out += '</tr></thead><tbody>';
                for (const r of body) {
                    out += '<tr>';
                    for (const c of r) out += `<td>${renderInline(c)}</td>`;
                    out += '</tr>';
                }
                out += '</tbody></table>\n';
                continue;
            }
        }

        // Unordered list
        if (/^\s*[-*+]\s+/.test(line)) {
            let items = [];
            while (i < lines.length && /^\s*[-*+]\s+/.test(lines[i])) {
                let item = lines[i].replace(/^\s*[-*+]\s+/, '');
                i++;
                // Continuation lines (indented)
                while (i < lines.length && /^\s{2,}\S/.test(lines[i])) {
                    item += ' ' + lines[i].trim();
                    i++;
                }
                items.push(item);
            }
            out += '<ul>';
            for (const it of items) out += `<li>${renderInline(it)}</li>`;
            out += '</ul>\n';
            continue;
        }

        // Ordered list
        if (/^\s*\d+\.\s+/.test(line)) {
            let items = [];
            while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
                let item = lines[i].replace(/^\s*\d+\.\s+/, '');
                i++;
                while (i < lines.length && /^\s{2,}\S/.test(lines[i])) {
                    item += ' ' + lines[i].trim();
                    i++;
                }
                items.push(item);
            }
            out += '<ol>';
            for (const it of items) out += `<li>${renderInline(it)}</li>`;
            out += '</ol>\n';
            continue;
        }

        // Blank line
        if (/^\s*$/.test(line)) {
            i++;
            continue;
        }

        // Paragraph (gather until blank or block element)
        let buf = [];
        while (i < lines.length &&
               !/^\s*$/.test(lines[i]) &&
               !/^#{1,6}\s/.test(lines[i]) &&
               !/^```/.test(lines[i]) &&
               !/^---+\s*$/.test(lines[i]) &&
               !/^>\s?/.test(lines[i]) &&
               !/^\s*[-*+]\s+/.test(lines[i]) &&
               !/^\s*\d+\.\s+/.test(lines[i]) &&
               !(/^\s*\|/.test(lines[i]) && i + 1 < lines.length && /^\s*\|?\s*:?-+/.test(lines[i + 1])) ) {
            buf.push(lines[i]);
            i++;
        }
        flushParagraph(buf);
    }
    return out;
}

function splitRow(row) {
    return row.replace(/^\s*\|/, '').replace(/\|\s*$/, '').split('|').map(c => c.trim());
}

function slug(s) {
    return s.toLowerCase()
        .replace(/<[^>]+>/g, '')
        .replace(/[^\w\s-]/g, '')
        .trim()
        .replace(/\s+/g, '-');
}

// ---------- Tiny syntax highlighter (GDScript / JSON / generic) ----------

function highlightCode(code, lang) {
    // Very light-touch highlighting. We tokenize comments and strings first
    // to avoid highlighting inside them, then keywords, numbers, functions.
    const keywords = {
        gdscript: /\b(func|var|const|if|elif|else|for|in|while|return|extends|class_name|signal|emit_signal|pass|true|false|null|match|break|continue|and|or|not|await|static|class|enum|export|onready|tool|yield)\b/g,
        json:     /\b(true|false|null)\b/g,
        py:       /\b(def|class|if|elif|else|for|in|while|return|import|from|as|with|try|except|finally|raise|pass|True|False|None|and|or|not|lambda|yield)\b/g,
        js:       /\b(function|var|let|const|if|else|for|while|return|class|extends|this|new|true|false|null|undefined|import|export|from|async|await|try|catch|throw|typeof)\b/g,
    };
    const kwRe = keywords[lang] || keywords.gdscript;
    const out = [];
    let s = mdEscape(code);

    // Preserve order: comments → strings → numbers → keywords → functions
    s = s.replace(/(#.*$|\/\/.*$)/gm,        '\x02\x01$1\x02\x02'); // comment
    s = s.replace(/("([^"\\]|\\.)*"|'([^'\\]|\\.)*')/g, '\x03\x01$1\x03\x02'); // string
    s = s.replace(/\b(\d+\.?\d*)\b/g,        '\x04\x01$1\x04\x02'); // number
    s = s.replace(kwRe,                      '\x05\x01$1\x05\x02'); // keyword
    s = s.replace(/\b([a-zA-Z_][a-zA-Z0-9_]*)(?=\()/g, '\x06\x01$1\x06\x02'); // function call

    s = s.replace(/\x02\x01(.*?)\x02\x02/g, '<span class="hl-comment">$1</span>');
    s = s.replace(/\x03\x01(.*?)\x03\x02/g, '<span class="hl-string">$1</span>');
    s = s.replace(/\x04\x01(.*?)\x04\x02/g, '<span class="hl-number">$1</span>');
    s = s.replace(/\x05\x01(.*?)\x05\x02/g, '<span class="hl-keyword">$1</span>');
    s = s.replace(/\x06\x01(.*?)\x06\x02/g, '<span class="hl-func">$1</span>');
    return s;
}

// ---------- Router / rendering ----------

function buildNav() {
    const nav = document.getElementById('sidenav-inner');
    let html = `
        <a class="nav-link" data-path="README.md" href="#/README.md">
            <span style="color: var(--accent)">▸</span> Overview
        </a>
    `;
    for (const section of DOCS) {
        html += `<div class="nav-section">
            <div class="nav-section-title" data-icon="${section.icon}">${section.title}</div>`;
        for (const page of section.pages) {
            const path = `${section.dir}/${page.file}`;
            const cls = page.stub ? 'nav-link stub' : 'nav-link';
            html += `<a class="${cls}" data-path="${path}" href="#/${path}">${page.title}</a>`;
        }
        html += `</div>`;
    }
    nav.innerHTML = html;
}

function buildTicker() {
    const track = document.getElementById('ticker-track');
    // Duplicate items so the animation loops seamlessly
    const items = TICKER_HEADLINES.concat(TICKER_HEADLINES)
        .map(h => `<span class="ticker-item">${h}</span>`).join('');
    track.innerHTML = items;
}

function pathFromHash() {
    const h = window.location.hash || '#/README.md';
    return h.replace(/^#\//, '').replace(/^#/, '') || 'README.md';
}

function findPageMeta(path) {
    if (path === 'README.md') return { title: 'Overview', section: null, stub: false };
    for (const section of DOCS) {
        for (const page of section.pages) {
            if (`${section.dir}/${page.file}` === path) {
                return { title: page.title, section: section.title, stub: !!page.stub };
            }
        }
    }
    return null;
}

async function renderPage() {
    const path = pathFromHash();
    const meta = findPageMeta(path);
    const main = document.getElementById('content');
    const tocEl = document.getElementById('toc-inner');

    // Highlight active nav link
    document.querySelectorAll('.nav-link').forEach(a => {
        a.classList.toggle('active', a.dataset.path === path);
    });

    // Update title
    document.title = meta ? `${meta.title} — Kill the Bill` : 'Kill the Bill';

    main.innerHTML = `<div class="loading">Loading // ${path}</div>`;
    tocEl.innerHTML = '';

    // If this is a known stub, short-circuit
    if (meta && meta.stub) {
        main.innerHTML = renderStubPage(path, meta);
        window.scrollTo(0, 0);
        return;
    }

    let text;
    try {
        const res = await fetch(path + '?v=' + Date.now());
        if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
        text = await res.text();
    } catch (err) {
        main.innerHTML = renderStubPage(path, meta, err.message);
        window.scrollTo(0, 0);
        return;
    }

    const breadcrumb = meta && meta.section
        ? `<div class="breadcrumb">${meta.section} <span class="sep">/</span> <span class="current">${meta.title}</span></div>`
        : `<div class="breadcrumb"><span class="current">${meta ? meta.title : path}</span></div>`;

    const html = renderMarkdown(text);
    main.innerHTML = breadcrumb + `<div class="content">${html}</div>` + renderFooter(path);

    rewriteLinks(main, path);
    buildToc(main, tocEl);

    // Scroll to hash anchor if present in URL (e.g. #/foo.md#section)
    const anchor = window.location.hash.split('#').slice(2).join('#');
    if (anchor) {
        requestAnimationFrame(() => {
            const el = document.getElementById(anchor);
            if (el) el.scrollIntoView({ behavior: 'smooth' });
        });
    } else {
        window.scrollTo(0, 0);
    }
}

function renderStubPage(path, meta, errMsg) {
    const title = meta ? meta.title : path;
    const section = meta ? meta.section : null;
    const msg = meta && meta.stub
        ? "This document is scoped in the roadmap but hasn't been written yet."
        : (errMsg ? `Could not load: ${mdEscape(errMsg)}` : "Document not found.");
    const breadcrumb = section
        ? `<div class="breadcrumb">${section} <span class="sep">/</span> <span class="current">${title}</span></div>`
        : `<div class="breadcrumb"><span class="current">${mdEscape(title)}</span></div>`;
    return `
        ${breadcrumb}
        <div class="stub-page">
            <div class="tag">${meta && meta.stub ? 'PLANNED' : 'MISSING'}</div>
            <h2>${mdEscape(title)}</h2>
            <p>${msg}</p>
        </div>
        ${renderFooter(path)}
    `;
}

function renderFooter(path) {
    return `
        <div class="page-footer">
            <span><span class="path">${path}</span></span>
            <span><a href="#/README.md">↑ overview</a></span>
        </div>
    `;
}

// Rewrite .md links so they route through the hash router.
// Resolve relative paths against the current document's directory.
function rewriteLinks(root, currentPath) {
    const baseDir = currentPath.includes('/')
        ? currentPath.substring(0, currentPath.lastIndexOf('/'))
        : '';
    root.querySelectorAll('a[href]').forEach(a => {
        const href = a.getAttribute('href');
        if (!href) return;
        // External
        if (/^(https?:)?\/\//.test(href) || href.startsWith('mailto:')) {
            a.setAttribute('target', '_blank');
            a.setAttribute('rel', 'noopener');
            return;
        }
        // Pure anchor (#section)
        if (href.startsWith('#')) return;
        // Split off anchor from path
        const hashIdx = href.indexOf('#');
        const filePart = hashIdx >= 0 ? href.slice(0, hashIdx) : href;
        const anchor = hashIdx >= 0 ? href.slice(hashIdx) : '';

        if (filePart.endsWith('.md')) {
            const resolved = resolvePath(baseDir, filePart);
            a.setAttribute('href', `#/${resolved}${anchor}`);
        } else if (filePart.startsWith('../../src/') || filePart.startsWith('../src/')) {
            // Link to source file — leave it, but mark it external visually
            a.setAttribute('data-source', 'true');
        }
    });
}

function resolvePath(baseDir, rel) {
    const parts = (baseDir ? baseDir.split('/') : []).concat(rel.split('/'));
    const out = [];
    for (const p of parts) {
        if (p === '..') out.pop();
        else if (p === '.' || p === '') continue;
        else out.push(p);
    }
    return out.join('/');
}

// Build the per-page table of contents from h2/h3/h4.
function buildToc(container, tocEl) {
    const headings = container.querySelectorAll('.content h2, .content h3, .content h4');
    if (!headings.length) { tocEl.innerHTML = ''; return; }

    let html = '<div class="toc-title">On this page</div><ul>';
    headings.forEach(h => {
        const level = h.tagName.toLowerCase();
        const id = h.id || slug(h.textContent);
        h.id = id;
        html += `<li class="toc-${level}"><a href="#/${pathFromHash()}#${id}">${h.textContent}</a></li>`;
    });
    html += '</ul>';
    tocEl.innerHTML = html;

    // Scroll-spy
    const links = Array.from(tocEl.querySelectorAll('a'));
    const io = new IntersectionObserver(entries => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const id = entry.target.id;
                links.forEach(a => a.classList.toggle(
                    'active', a.getAttribute('href').endsWith('#' + id)
                ));
            }
        });
    }, { rootMargin: '-40% 0px -55% 0px' });
    headings.forEach(h => io.observe(h));
}

// ---------- Boot ----------

function init() {
    buildNav();
    buildTicker();
    renderPage();
    window.addEventListener('hashchange', renderPage);

    // Mobile menu toggle
    const toggle = document.getElementById('menu-toggle');
    const nav = document.getElementById('sidenav');
    if (toggle && nav) {
        toggle.addEventListener('click', () => nav.classList.toggle('open'));
        document.addEventListener('click', e => {
            if (window.innerWidth > 800) return;
            if (!nav.contains(e.target) && !toggle.contains(e.target)) {
                nav.classList.remove('open');
            }
        });
    }
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}

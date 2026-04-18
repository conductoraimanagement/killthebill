// =============================================================
// nav.js — Shared Navigation Component for Kill The Bill Docs
// =============================================================
// Single source of truth for the sidebar nav. Injected into every
// page via <script src="nav.js">. No more copy-pasting nav HTML.

(function() {
  'use strict';

  // Navigation structure — edit HERE to update all pages
  const NAV_SECTIONS = [
    {
      title: 'OVERVIEW',
      links: [
        { text: 'Dashboard', href: '/index.html' },
        { text: 'Project Status', href: '/status.html' }
      ]
    },
    {
      title: 'ROADMAP',
      links: [
        { text: 'Phase 1: Architecture', href: '/phases/phase1-architecture.html' },
        { text: 'Phase 2: Prototyping', href: '/phases/phase2-prototyping.html' },
        { text: 'Phase 3: Core Systems', href: '/phases/phase3-core-systems.html' },
        { text: 'Phase 4: Gameplay', href: '/phases/phase4-gameplay.html' }
      ]
    },
    {
      title: 'CORE SINGLETONS',
      links: [
        { text: 'WorldDirector', href: '/core/world-director.html' },
        { text: 'PlayerManager', href: '/core/player-manager.html' },
        { text: 'PopulationDirector', href: '/core/population-director.html' },
        { text: 'RegionGenerator', href: '/core/region-generator.html' },
        { text: 'LLMManager', href: '/core/llm-manager.html' }
      ]
    },
    {
      title: 'ENTITIES',
      links: [
        { text: 'NPC: Nature & Nurture', href: '/entities/npc-ai.html' },
        { text: 'Oligarchs & Billionaires', href: '/entities/oligarchs.html' },
        { text: 'Relationships & Agents', href: '/entities/relationships.html' },
        { text: 'Social Fabric Engine', href: '/entities/social-fabric.html' }
      ]
    },
    {
      title: 'SYSTEMS',
      links: [
        { text: 'NetFeed & Events', href: '/systems/netfeed.html' },
        { text: 'Heat & Evasion', href: '/systems/heat-evasion.html' },
        { text: 'Combat Mechanics', href: '/systems/combat.html' },
        { text: 'Regions & Travel', href: '/systems/macro-world.html' },
        { text: 'Victory Conditions', href: '/systems/victory-conditions.html' }
      ]
    }
  ];

  // Resolve the base path for relative URLs
  function getBasePath() {
    const path = window.location.pathname;
    const depth = (path.match(/\//g) || []).length;
    // If we're in a subdirectory (core/, entities/, etc.), go up one level
    if (path.includes('/core/') || path.includes('/entities/') || 
        path.includes('/systems/') || path.includes('/phases/') ||
        path.includes('/general/') || path.includes('/backend/') ||
        path.includes('/frontend/')) {
      return '..';
    }
    return '.';
  }

  function buildNav() {
    const sidebar = document.getElementById('sidebar');
    if (!sidebar) return;

    const base = getBasePath();
    const currentPath = window.location.pathname;

    // Logo / Title
    let html = '<div class="sidebar-header">';
    html += '<button class="sidebar-toggle" id="sidebarToggle" aria-label="Toggle navigation">☰</button>';
    html += '<a href="' + base + '/index.html" class="sidebar-logo">KILL THE BILL</a>';
    html += '</div>';

    // Search
    html += '<div class="search-container">';
    html += '<input type="text" id="navSearch" class="nav-search" placeholder="Search docs..." autocomplete="off">';
    html += '</div>';

    // Nav links
    html += '<div class="nav-links" id="navLinks">';
    
    NAV_SECTIONS.forEach(function(section, sectionIndex) {
      const sectionId = 'nav-section-' + sectionIndex;
      const isCollapsed = localStorage.getItem(sectionId) === 'collapsed';
      
      html += '<div class="nav-section-header" data-section="' + sectionId + '">';
      html += '<span class="nav-section-title">' + section.title + '</span>';
      html += '<span class="nav-section-chevron ' + (isCollapsed ? 'collapsed' : '') + '">▾</span>';
      html += '</div>';
      html += '<div class="nav-section-links ' + (isCollapsed ? 'collapsed' : '') + '" id="' + sectionId + '">';
      
      section.links.forEach(function(link) {
        const fullHref = base + link.href;
        const isActive = currentPath.endsWith(link.href) || 
                         currentPath.endsWith(link.href.replace('/', '\\'));
        html += '<a href="' + fullHref + '"' + (isActive ? ' class="active"' : '') + ' data-search="' + link.text.toLowerCase() + '">';
        html += link.text;
        html += '</a>';
      });
      
      html += '</div>';
    });
    
    html += '</div>';
    sidebar.innerHTML = html;

    // Build breadcrumbs
    buildBreadcrumbs(base);

    // Attach event listeners
    attachListeners();
  }

  function buildBreadcrumbs(base) {
    const breadcrumbEl = document.getElementById('breadcrumbs');
    if (!breadcrumbEl) return;

    const currentPath = window.location.pathname;
    let currentPage = null;
    let currentSection = null;

    NAV_SECTIONS.forEach(function(section) {
      section.links.forEach(function(link) {
        if (currentPath.endsWith(link.href)) {
          currentPage = link.text;
          currentSection = section.title;
        }
      });
    });

    if (currentSection && currentPage) {
      breadcrumbEl.innerHTML = '<span class="breadcrumb-section">' + currentSection + '</span>' +
                               '<span class="breadcrumb-sep">›</span>' +
                               '<span class="breadcrumb-page">' + currentPage + '</span>';
    }
  }

  function attachListeners() {
    // Collapsible sections
    document.querySelectorAll('.nav-section-header').forEach(function(header) {
      header.addEventListener('click', function() {
        const sectionId = this.dataset.section;
        const links = document.getElementById(sectionId);
        const chevron = this.querySelector('.nav-section-chevron');
        
        if (links.classList.contains('collapsed')) {
          links.classList.remove('collapsed');
          chevron.classList.remove('collapsed');
          localStorage.setItem(sectionId, 'expanded');
        } else {
          links.classList.add('collapsed');
          chevron.classList.add('collapsed');
          localStorage.setItem(sectionId, 'collapsed');
        }
      });
    });

    // Search
    const searchInput = document.getElementById('navSearch');
    if (searchInput) {
      searchInput.addEventListener('input', function() {
        const query = this.value.toLowerCase().trim();
        document.querySelectorAll('.nav-section-links a').forEach(function(link) {
          const text = link.dataset.search || link.textContent.toLowerCase();
          link.style.display = (!query || text.includes(query)) ? '' : 'none';
        });
        // Show all sections when searching
        if (query) {
          document.querySelectorAll('.nav-section-links').forEach(function(el) {
            el.classList.remove('collapsed');
          });
        }
      });
    }

    // Sidebar toggle (mobile)
    const toggleBtn = document.getElementById('sidebarToggle');
    const sidebar = document.getElementById('sidebar');
    if (toggleBtn && sidebar) {
      toggleBtn.addEventListener('click', function() {
        sidebar.classList.toggle('sidebar-open');
      });
    }
  }

  // Build nav when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', buildNav);
  } else {
    buildNav();
  }
})();

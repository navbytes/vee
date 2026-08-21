/* Vee site — progressive enhancement. No dependencies, self-contained. */
(function () {
  "use strict";

  var reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var finePointer = window.matchMedia && window.matchMedia("(pointer: fine)").matches;

  /* ---- Mobile nav toggle ------------------------------------------------- */
  var toggle = document.querySelector(".nav-toggle");
  var links = document.getElementById("nav-links");
  if (toggle && links) {
    toggle.addEventListener("click", function () {
      var open = links.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    links.addEventListener("click", function (e) {
      if (e.target.closest("a")) {
        links.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      }
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && links.classList.contains("open")) {
        links.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
        toggle.focus();
      }
    });
  }

  /* ---- The signature: live menu-bar demo --------------------------------- */
  (function () {
    var win = document.querySelector(".macwin");
    if (!win) return;
    var openItem = win.querySelector(".mb-item.is-open");
    var cpuEls = win.querySelectorAll(".mb-cpu");
    var btcEls = win.querySelectorAll(".mb-btc");

    // Reduced motion: freeze on the fully-shown frame, no looping.
    if (reduce) { win.setAttribute("data-phase", "shown"); return; }

    var timers = [];
    var running = false;

    function clear() { timers.forEach(clearTimeout); timers = []; }
    function later(fn, ms) { timers.push(setTimeout(fn, ms)); }

    function refreshValues() {
      var cpu = 7 + Math.floor(Math.random() * 13); // 7–19%
      cpuEls.forEach(function (e) { e.textContent = "CPU " + cpu + "%"; });
      var btc = 66700 + Math.floor(Math.random() * 1100);
      btcEls.forEach(function (e) { e.textContent = "$" + btc.toLocaleString("en-US"); });
    }

    function cycle() {
      if (!running) return;
      win.setAttribute("data-phase", "idle");
      if (openItem) openItem.classList.remove("is-running");
      later(function () {
        if (!running) return;
        refreshValues();
        if (openItem) openItem.classList.add("is-running");
        win.setAttribute("data-phase", "running"); // rows stream in, checkmark pops
        later(function () {
          if (!running) return;
          if (openItem) openItem.classList.remove("is-running");
          win.setAttribute("data-phase", "shown");  // hold on the result
          later(cycle, 2900);
        }, 1250);
      }, 520);
    }

    function start() { if (!running) { running = true; cycle(); } }
    function stop() { running = false; clear(); }

    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (en) { en.isIntersecting ? start() : stop(); });
      }, { threshold: 0.25 });
      io.observe(win);
    } else {
      start();
    }
  })();

  /* ---- Magnetic primary CTA ---------------------------------------------- */
  if (!reduce && finePointer) {
    document.querySelectorAll(".magnetic").forEach(function (btn) {
      var strength = 0.26;
      btn.addEventListener("pointermove", function (e) {
        var r = btn.getBoundingClientRect();
        var x = (e.clientX - r.left - r.width / 2) * strength;
        var y = (e.clientY - r.top - r.height / 2) * strength;
        btn.style.transform = "translate(" + x.toFixed(1) + "px," + y.toFixed(1) + "px)";
      });
      btn.addEventListener("pointerleave", function () { btn.style.transform = ""; });
    });
  }

  /* ---- Scroll reveals: IntersectionObserver fallback --------------------- */
  // Native `animation-timeline: view()` handles this where supported (see CSS).
  // Only wire the JS fallback when native isn't available and motion is allowed.
  (function () {
    var nodes = document.querySelectorAll(".reveal");
    if (!nodes.length) return;
    var nativeOK = window.CSS && CSS.supports && CSS.supports("animation-timeline", "view()");
    if (reduce || nativeOK) return; // reduced-motion: CSS leaves content visible
    if (!("IntersectionObserver" in window)) {
      nodes.forEach(function (el) { el.classList.add("in"); });
      return;
    }
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -8% 0px" });
    nodes.forEach(function (el) { io.observe(el); });
  })();

  /* ---- Docs search (Pagefind) -------------------------------------------- */
  // Progressive enhancement: the index is static and the sidebar nav works
  // without this. If PagefindUI failed to load, leave the container empty
  // rather than showing a dead input.
  (function () {
    var host = document.getElementById("docs-search");
    if (!host || typeof PagefindUI === "undefined") return;
    new PagefindUI({
      element: "#docs-search",
      baseUrl: "/",
      showImages: false,
      showSubResults: true,
      resetStyles: false,
      translations: { placeholder: "Search docs" },
    });
    // `/` focuses search, the shortcut every docs site has. Ignore it while
    // the user is already typing somewhere.
    document.addEventListener("keydown", function (e) {
      if (e.key !== "/" || e.metaKey || e.ctrlKey || e.altKey) return;
      var t = e.target;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) return;
      var input = host.querySelector("input");
      if (input) { e.preventDefault(); input.focus(); }
    });
  })();

  /* ---- Copy buttons on code blocks --------------------------------------- */
  // Every sample on these pages is meant to be run, so make taking it cheap.
  (function () {
    var blocks = document.querySelectorAll(".docs-content pre");
    if (!blocks.length || !navigator.clipboard) return;
    blocks.forEach(function (pre) {
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "copy-btn";
      btn.textContent = "Copy";
      btn.setAttribute("aria-label", "Copy code to clipboard");
      btn.addEventListener("click", function () {
        navigator.clipboard.writeText(pre.innerText).then(function () {
          btn.textContent = "Copied";
          btn.classList.add("copied");
          setTimeout(function () {
            btn.textContent = "Copy";
            btn.classList.remove("copied");
          }, 1600);
        });
      });
      pre.appendChild(btn);
    });
  })();
})();

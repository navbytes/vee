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
})();

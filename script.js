const navToggle = document.querySelector(".nav-toggle");
const siteNav = document.querySelector(".site-nav");

if (navToggle && siteNav) {
  navToggle.addEventListener("click", () => {
    const isOpen = siteNav.classList.toggle("is-open");
    navToggle.setAttribute("aria-expanded", String(isOpen));
  });

  siteNav.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      siteNav.classList.remove("is-open");
      navToggle.setAttribute("aria-expanded", "false");
    });
  });
}

const activePage = document.body.dataset.page;

document.querySelectorAll("[data-nav]").forEach((link) => {
  if (link.dataset.nav === activePage) {
    link.setAttribute("aria-current", "page");
  }
});

const reveals = document.querySelectorAll("[data-reveal]");

if ("IntersectionObserver" in window && reveals.length > 0) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.18 }
  );

  reveals.forEach((item) => observer.observe(item));
} else {
  reveals.forEach((item) => item.classList.add("is-visible"));
}

const ESTIMATE_LABELS = {
  pages: {
    small: "1 bis 3 Seiten",
    medium: "4 bis 6 Seiten",
    large: "7 bis 10 Seiten",
    xlarge: "Mehr als 10 Seiten",
  },
  content: {
    ready: "Texte und Inhalte sind weitgehend bereit",
    partial: "Teile sind vorhanden",
    new: "Es soll inhaltlich neu aufgebaut werden",
  },
  design: {
    clean: "Klar und fokussiert",
    premium: "Hochwertig und modern",
    individual: "Auff\u00e4lliger und individueller",
  },
  features: {
    contact: "Kontaktformular",
    booking: "Terminbuchung",
    calendar: "Kalender-Anbindung",
    faq: "FAQ-Bereich",
    gallery: "Google-Bewertungen",
    blog: "Blog oder News",
    multilingual: "Mehrsprachig",
    whatsapp: "WhatsApp oder Schnellkontakt",
    workflow: "Anfrage-Workflow oder Rechner",
    ai: "KI-Funktion",
  },
  support: {
    none: "Noch offen",
    starter: "Starter",
    plus: "Plus",
    pro: "Pro",
  },
};

const FEATURE_WEIGHTS = {
  contact: 1,
  booking: 3,
  calendar: 2,
  faq: 1,
  gallery: 1,
  blog: 2,
  multilingual: 3,
  whatsapp: 1,
  workflow: 3,
  ai: 4,
};

function getCheckedValues(root, name) {
  return Array.from(root.querySelectorAll(`input[name="${name}"]:checked`)).map((input) => input.value);
}

function mapLeadPlan(value) {
  if (value === "Starter") {
    return "starter";
  }

  if (value === "Plus") {
    return "plus";
  }

  if (value === "Pro") {
    return "pro";
  }

  return "none";
}

function mapLeadTimeline(value) {
  if (value === "so schnell wie m\u00f6glich") {
    return "fast";
  }

  if (value === "in 2 bis 4 Wochen") {
    return "soon";
  }

  return "normal";
}

function describeFeatures(features) {
  if (features.length === 0) {
    return "ohne besondere Zusatzfunktionen";
  }

  if (features.length === 1) {
    return `mit ${ESTIMATE_LABELS.features[features[0]]}`;
  }

  return `mit ${features.length} Zusatzfunktionen`;
}

function computeEstimate({ pages, content, design, timeline, support, features }) {
  const scoreMap = {
    pages: {
      small: 0,
      medium: 2,
      large: 4,
      xlarge: 6,
    },
    content: {
      ready: 0,
      partial: 2,
      new: 4,
    },
    design: {
      clean: 1,
      premium: 3,
      individual: 5,
    },
    timeline: {
      normal: 0,
      soon: 1,
      fast: 3,
    },
  };

  const safePages = pages || "small";
  const safeContent = content || "ready";
  const safeDesign = design || "clean";
  const safeTimeline = timeline || "normal";
  const safeSupport = support || "none";
  const safeFeatures = Array.isArray(features) ? features : [];

  let score = 0;
  score += scoreMap.pages[safePages] || 0;
  score += scoreMap.content[safeContent] || 0;
  score += scoreMap.design[safeDesign] || 0;
  score += scoreMap.timeline[safeTimeline] || 0;
  score += safeFeatures.reduce((total, feature) => total + (FEATURE_WEIGHTS[feature] || 0), 0);

  let range = "ca. 500 - 749 \u20ac";
  let note = "Schlanker Einstieg";

  if (score > 5 && score <= 8) {
    range = "ca. 750 - 999 \u20ac";
    note = "Kompakte Standardseite";
  } else if (score > 8 && score <= 12) {
    range = "ca. 1.000 - 1.299 \u20ac";
    note = "Saubere Unternehmensseite";
  } else if (score > 12 && score <= 16) {
    range = "ca. 1.300 - 1.599 \u20ac";
    note = "St\u00e4rkeres Projekt";
  } else if (score > 16 && score <= 20) {
    range = "ca. 1.600 - 1.799 \u20ac";
    note = "Umfangreicher Auftritt";
  } else if (score > 20) {
    range = "ca. 1.800 - 1.999 \u20ac";
    note = "Komplexeres Workflow-Projekt";
  }

  let recommendedPlan = "Starter";

  if (safeSupport === "plus") {
    recommendedPlan = "Plus";
  }

  if (safeSupport === "pro") {
    recommendedPlan = "Pro";
  }

  if (safeSupport === "none" || safeSupport === "starter") {
    if (score > 10) {
      recommendedPlan = "Plus";
    }

    if (score > 16) {
      recommendedPlan = "Pro";
    }
  }

  if (
    safeFeatures.includes("booking") ||
    safeFeatures.includes("calendar") ||
    safeFeatures.includes("workflow")
  ) {
    recommendedPlan = recommendedPlan === "Pro" ? "Pro" : "Plus";
  }

  if (safeFeatures.includes("ai")) {
    recommendedPlan = "Pro";
  }

  const pagesLabel =
    {
      small: "kompakte Website",
      medium: "klassische Website mit mehreren Unterseiten",
      large: "umfangreichere Website",
      xlarge: "gr\u00f6\u00dfere Website",
    }[safePages] || "Website";

  const designLabel =
    {
      clean: "mit klarem Aufbau",
      premium: "mit hochwertigem Look",
      individual: "mit individuellerem Look",
    }[safeDesign] || "mit passendem Look";

  const summary = `Das wirkt aktuell wie eine ${pagesLabel} ${designLabel} ${describeFeatures(safeFeatures)}.`;

  return {
    range,
    note,
    summary,
    recommendedPlan,
    values: {
      pages: safePages,
      content: safeContent,
      design: safeDesign,
      timeline: safeTimeline,
      support: safeSupport,
      features: safeFeatures,
    },
  };
}

function fillEstimateOutputs(root, result) {
  const rangeNode = root.querySelector("[data-price-range], [data-inline-price-range]");
  const noteNode = root.querySelector("[data-price-note], [data-inline-price-note]");
  const summaryNode = root.querySelector("[data-price-summary], [data-inline-price-summary]");
  const planNode = root.querySelector("[data-price-plan]");

  if (rangeNode) {
    rangeNode.textContent = result.range;
  }

  if (noteNode) {
    noteNode.textContent = result.note;
  }

  if (summaryNode) {
    summaryNode.textContent = `${result.summary} Der genaue Preis wird danach individuell festgelegt.`;
  }

  if (planNode) {
    planNode.textContent = result.recommendedPlan;
  }
}

function setupEstimateDrawer(form) {
  const goalField = form.querySelector("[data-goal-field]");
  const drawer = form.querySelector("[data-estimate-drawer]");
  const toggle = form.querySelector("[data-estimate-toggle]");
  const panel = form.querySelector("[data-estimate-panel]");

  if (!drawer || !toggle || !panel) {
    return;
  }

  const setOpen = (open) => {
    drawer.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
    panel.hidden = !open;
  };

  toggle.addEventListener("click", () => {
    const isOpen = toggle.getAttribute("aria-expanded") === "true";
    setOpen(!isOpen);
  });

  if (goalField) {
    goalField.addEventListener("focus", () => setOpen(true));
    goalField.addEventListener("input", () => setOpen(true));
  }
}

function syncLeadAiRequirement(form) {
  const aiChecked = form.querySelector('input[name="estimate_features"][value="ai"]:checked');
  const planField = form.querySelector('select[name="plan"]');
  const hint = form.querySelector("[data-plan-hint]");

  if (aiChecked && planField && planField.value !== "Pro") {
    planField.value = "Pro";
  }

  if (hint) {
    hint.hidden = !aiChecked;
  }
}

function updateLeadEstimate(form) {
  const data = new FormData(form);
  const result = computeEstimate({
    pages: data.get("estimate_pages")?.toString() || "small",
    content: data.get("estimate_content")?.toString() || "ready",
    design: data.get("estimate_design")?.toString() || "clean",
    timeline: mapLeadTimeline(data.get("timeline")?.toString() || ""),
    support: mapLeadPlan(data.get("plan")?.toString() || ""),
    features: getCheckedValues(form, "estimate_features"),
  });

  fillEstimateOutputs(form, result);
  return result;
}

function estimateWasUsed(form) {
  return form.dataset.estimateUsed === "true";
}

function getLeadEstimateLines(result) {
  const featureLabels = result.values.features.map((feature) => ESTIMATE_LABELS.features[feature]);
  const featureText = featureLabels.length > 0 ? featureLabels.join(", ") : "Keine ausgew\u00e4hlt";

  return [
    "",
    "Preis-Checkliste:",
    `Seitenumfang: ${ESTIMATE_LABELS.pages[result.values.pages]}`,
    `Inhalte: ${ESTIMATE_LABELS.content[result.values.content]}`,
    `Designanspruch: ${ESTIMATE_LABELS.design[result.values.design]}`,
    `Zusatzfunktionen: ${featureText}`,
    `Grobe Preisspanne: ${result.range}`,
    `Einordnung: ${result.note}`,
    `Empfohlenes Monatspaket: ${result.recommendedPlan}`,
  ];
}

const leadForm = document.querySelector("#lead-form");

if (leadForm) {
  setupEstimateDrawer(leadForm);
  updateLeadEstimate(leadForm);

  leadForm.querySelectorAll("[data-estimate-field]").forEach((field) => {
    field.addEventListener("input", () => {
      leadForm.dataset.estimateUsed = "true";
      syncLeadAiRequirement(leadForm);
      updateLeadEstimate(leadForm);
    });

    field.addEventListener("change", () => {
      leadForm.dataset.estimateUsed = "true";
      syncLeadAiRequirement(leadForm);
      updateLeadEstimate(leadForm);
    });
  });

  leadForm.querySelectorAll('input[name="timeline"], select[name="plan"]').forEach((field) => {
    field.addEventListener("change", () => {
      syncLeadAiRequirement(leadForm);
      updateLeadEstimate(leadForm);
    });
  });

  leadForm.addEventListener("submit", (event) => {
    event.preventDefault();

    syncLeadAiRequirement(leadForm);
    const result = updateLeadEstimate(leadForm);
    const data = new FormData(leadForm);
    const name = data.get("name")?.toString().trim() || "Neue Anfrage";
    const company = data.get("company")?.toString().trim() || "Unbekanntes Unternehmen";
    const industry = data.get("industry")?.toString().trim() || "Unternehmen";
    const plan = data.get("plan")?.toString().trim() || "Noch offen";
    const projectType = data.get("project_type")?.toString().trim() || "Ich will direkt eine Website";
    const timeline = data.get("timeline")?.toString().trim() || "ohne festen Termin";
    const email = data.get("email")?.toString().trim() || "keine E-Mail angegeben";
    const goal = data.get("goal")?.toString().trim() || "Kein Ziel angegeben";

    const lines = [
      "Neue Anfrage fuer Skysites",
      "",
      `Ansprechpartner: ${name}`,
      `Unternehmen: ${company}`,
      `Branche: ${industry}`,
      `Monatspaket: ${plan}`,
      `Projektwunsch: ${projectType}`,
      `Zeitraum: ${timeline}`,
      `E-Mail: ${email}`,
      "",
      "Ziel der Website:",
      goal,
    ];

    if (estimateWasUsed(leadForm)) {
      lines.push(...getLeadEstimateLines(result));
    }

    lines.push(
      "",
      "Projektbrief:",
      `${company} sucht ${projectType} fuer ein ${industry.toLowerCase()} und interessiert sich fuer das Monatspaket ${plan}. Zeitraum: ${timeline}. Ziel: ${goal}`
    );

    if (estimateWasUsed(leadForm)) {
      lines.push(`Preisrahmen laut Checkliste: ${result.range}. Passend dazu wirkt aktuell ${result.recommendedPlan}.`);
    }

    const subject = encodeURIComponent(`Neue Skysites Anfrage - ${company}`);
    const body = encodeURIComponent(lines.join("\n"));

    window.location.href = `mailto:hallo@skysites.de?subject=${subject}&body=${body}`;
  });
}

function syncPriceFinderAiRequirement(form) {
  const aiChecked = form.querySelector('input[name="features"][value="ai"]:checked');

  if (!aiChecked) {
    return;
  }

  const proField = form.querySelector('input[name="support"][value="pro"]');

  if (proField) {
    proField.checked = true;
  }
}

const priceFinderForm = document.querySelector("#price-finder-form");

if (priceFinderForm) {
  const updatePriceFinder = () => {
    syncPriceFinderAiRequirement(priceFinderForm);

    const data = new FormData(priceFinderForm);
    const result = computeEstimate({
      pages: data.get("pages")?.toString() || "small",
      content: data.get("content")?.toString() || "ready",
      design: data.get("design")?.toString() || "clean",
      timeline: data.get("timeline")?.toString() || "normal",
      support: data.get("support")?.toString() || "none",
      features: getCheckedValues(priceFinderForm, "features"),
    });

    fillEstimateOutputs(document, result);
  };

  priceFinderForm.addEventListener("input", updatePriceFinder);
  priceFinderForm.addEventListener("change", updatePriceFinder);
  updatePriceFinder();
}

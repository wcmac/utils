const grid = document.getElementById("grid");
const searchFields = {
  prompt: document.getElementById("search-prompt"),
  negative_prompt: document.getElementById("search-negative"),
  filename: document.getElementById("search-filename"),
  aspect: document.getElementById("search-aspect"),
};
const countEl = document.getElementById("count-bar");
const loadMoreBtn = document.getElementById("load-more");
const layout = document.getElementById("layout");
const resizer = document.getElementById("resizer");
const detailPane = document.getElementById("detail-pane");
const detailImg = document.getElementById("detail-img");
const detailOpenBtn = document.querySelector("#detail-img-wrap .open-overlay");

const PAGE_SIZE = 1000;
const MIN_PANE_WIDTH = 240;
let debounceTimer = null;
let loadedCount = 0;
let totalCount = 0;
let selectedCell = null;
let selectedId = null;
let paneVisible = false;

function currentCriteria() {
  const c = {};
  for (const [key, input] of Object.entries(searchFields)) {
    if (input.value) c[key] = input.value;
  }
  return c;
}

function restoreFromUrl() {
  const params = new URLSearchParams(location.search);
  for (const [key, input] of Object.entries(searchFields)) {
    const v = params.get(key);
    if (v) input.value = v;
  }
}

function syncUrl() {
  const qs = new URLSearchParams(currentCriteria()).toString();
  const newUrl = qs ? `${location.pathname}?${qs}` : location.pathname;
  history.replaceState(null, "", newUrl);
}

function runSearch() {
  loadedCount = 0;
  grid.innerHTML = "";
  syncUrl();
  fetchPage();
}

function fetchPage() {
  const params = new URLSearchParams(currentCriteria());
  params.set("offset", loadedCount);
  params.set("limit", PAGE_SIZE);
  fetch(`/api/search?${params.toString()}`)
    .then((r) => r.json())
    .then((data) => {
      totalCount = data.total;
      loadedCount += data.items.length;
      appendGrid(data.items);
      updateCount();
      loadMoreBtn.classList.toggle("hidden", loadedCount >= totalCount);
    });
}

function updateCount() {
  countEl.textContent = totalCount === 0
    ? "No results"
    : `Showing ${loadedCount.toLocaleString()} of ${totalCount.toLocaleString()} results`;
}

function openImage(id) {
  fetch(`/api/open/${id}`, { method: "POST" });
}

function appendGrid(items) {
  for (const item of items) {
    const cell = document.createElement("div");
    cell.className = "thumb";

    const img = document.createElement("img");
    img.src = `/thumb/${item.id}`;
    img.loading = "lazy";
    img.alt = item.positive_prompt || "";
    cell.appendChild(img);

    const openBtn = document.createElement("button");
    openBtn.className = "open-overlay";
    openBtn.title = "Open in default app";
    openBtn.innerHTML = "&#8599;";
    openBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      openImage(item.id);
    });
    cell.appendChild(openBtn);

    cell.addEventListener("click", () => selectImage(item.id, cell));
    grid.appendChild(cell);
  }
}

function showPane() {
  if (paneVisible) return;
  paneVisible = true;
  detailPane.classList.remove("hidden");
  resizer.classList.remove("hidden");
  detailPane.style.width = `${layout.getBoundingClientRect().width * 0.5}px`;
}

function selectImage(id, cell) {
  if (selectedCell) selectedCell.classList.remove("selected");
  selectedCell = cell;
  selectedId = id;
  cell.classList.add("selected");
  showPane();

  fetch(`/api/image/${id}`)
    .then((r) => r.json())
    .then((detail) => {
      detailImg.src = `/full/${id}`;
      document.getElementById("meta-positive").textContent = detail.positive_prompt || "(none)";
      document.getElementById("meta-negative").textContent = detail.negative_prompt || "(none)";
      const params = [];
      if (detail.model) params.push(`Model: ${detail.model}`);
      if (detail.sampler) params.push(`Sampler: ${detail.sampler}`);
      if (detail.seed) params.push(`Seed: ${detail.seed}`);
      if (detail.steps) params.push(`Steps: ${detail.steps}`);
      if (detail.cfg_scale) params.push(`CFG scale: ${detail.cfg_scale}`);
      if (detail.width && detail.height) params.push(`Size: ${detail.width}x${detail.height}`);
      document.getElementById("meta-params").textContent = params.join("\n") || "(none)";
      document.getElementById("meta-path").textContent = detail.path;
    });
}

function onResizerDrag(e) {
  const layoutRect = layout.getBoundingClientRect();
  const maxWidth = layoutRect.width - MIN_PANE_WIDTH;
  let newWidth = layoutRect.right - e.clientX;
  newWidth = Math.max(MIN_PANE_WIDTH, Math.min(maxWidth, newWidth));
  detailPane.style.width = `${newWidth}px`;
}

function stopResizerDrag() {
  document.removeEventListener("mousemove", onResizerDrag);
  document.removeEventListener("mouseup", stopResizerDrag);
}

resizer.addEventListener("mousedown", (e) => {
  e.preventDefault();
  document.addEventListener("mousemove", onResizerDrag);
  document.addEventListener("mouseup", stopResizerDrag);
});

detailOpenBtn.addEventListener("click", () => {
  if (selectedId != null) openImage(selectedId);
});

for (const input of Object.values(searchFields)) {
  input.addEventListener("input", () => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(runSearch, 250);
  });
}

loadMoreBtn.addEventListener("click", fetchPage);

restoreFromUrl();
runSearch();

const grid = document.getElementById("grid");
const searchInput = document.getElementById("search");
const countEl = document.getElementById("count");
const loadMoreBtn = document.getElementById("load-more");
const lightbox = document.getElementById("lightbox");
const lightboxImg = document.getElementById("lightbox-img");
const lightboxClose = document.getElementById("lightbox-close");

const PAGE_SIZE = 60;
let debounceTimer = null;
let loadedCount = 0;
let totalCount = 0;

function runSearch() {
  loadedCount = 0;
  grid.innerHTML = "";
  fetchPage();
}

function fetchPage() {
  const q = searchInput.value;
  fetch(`/api/search?q=${encodeURIComponent(q)}&offset=${loadedCount}`)
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
    ? "no results"
    : `${loadedCount} of ${totalCount}`;
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
    cell.addEventListener("click", () => openLightbox(item.id));
    grid.appendChild(cell);
  }
}

function openLightbox(id) {
  fetch(`/api/image/${id}`)
    .then((r) => r.json())
    .then((detail) => {
      lightboxImg.src = `/full/${id}`;
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
      lightbox.classList.remove("hidden");
    });
}

function closeLightbox() {
  lightbox.classList.add("hidden");
  lightboxImg.src = "";
}

searchInput.addEventListener("input", () => {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(runSearch, 250);
});

loadMoreBtn.addEventListener("click", fetchPage);

lightboxClose.addEventListener("click", closeLightbox);
lightbox.addEventListener("click", (e) => {
  if (e.target === lightbox) closeLightbox();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") closeLightbox();
});

runSearch();

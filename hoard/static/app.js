const grid = document.getElementById("grid");
const searchInput = document.getElementById("search");
const countEl = document.getElementById("count-bar");
const loadMoreBtn = document.getElementById("load-more");
const detailEmpty = document.getElementById("detail-empty");
const detailContent = document.getElementById("detail-content");
const detailImg = document.getElementById("detail-img");

const PAGE_SIZE = 60;
let debounceTimer = null;
let loadedCount = 0;
let totalCount = 0;
let selectedCell = null;

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
    ? "No results"
    : `Showing ${loadedCount.toLocaleString()} of ${totalCount.toLocaleString()} results`;
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
    cell.addEventListener("click", () => selectImage(item.id, cell));
    grid.appendChild(cell);
  }
}

function selectImage(id, cell) {
  if (selectedCell) selectedCell.classList.remove("selected");
  selectedCell = cell;
  cell.classList.add("selected");

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
      detailEmpty.classList.add("hidden");
      detailContent.classList.remove("hidden");
    });
}

searchInput.addEventListener("input", () => {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(runSearch, 250);
});

loadMoreBtn.addEventListener("click", fetchPage);

runSearch();

// Portfolio frontend — boilerplate, single file on purpose.
// All markup and styles are generated here; index.html only loads this file.
// Extend by adding more sections to renderApp() and more routes in main.py.

const STYLES = `
  :root {
    --bg: #0f1115; --surface: #171a21; --text: #e8e9ec; --muted: #9aa0ab;
    --accent: #5b8cff; --border: #262a33; font-family: system-ui, sans-serif;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); line-height: 1.6; }
  header { padding: 3rem 1.5rem; text-align: center; border-bottom: 1px solid var(--border); }
  header h1 { font-size: 2.2rem; }
  header p { color: var(--muted); margin-top: .5rem; }
  main { max-width: 800px; margin: 0 auto; padding: 2rem 1.5rem; }
  section { margin-bottom: 3rem; }
  section h2 { margin-bottom: 1rem; font-size: 1.4rem; }
  .card { background: var(--surface); border: 1px solid var(--border); border-radius: 10px;
          padding: 1.25rem; margin-bottom: 1rem; }
  .card a { color: var(--accent); text-decoration: none; }
  .card-row { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; }
  .card-actions { display: flex; gap: .5rem; flex-shrink: 0; }
  .card-actions button { width: auto; padding: .35rem .7rem; font-size: .8rem; }
  .btn-secondary { background: transparent; border: 1px solid var(--border); color: var(--text); }
  .btn-danger { background: transparent; border: 1px solid #ff6b6b; color: #ff6b6b; }
  form { display: flex; flex-direction: column; gap: .75rem; }
  input, textarea { background: var(--surface); border: 1px solid var(--border); color: var(--text);
                     padding: .7rem; border-radius: 8px; font: inherit; }
  button { background: var(--accent); color: #fff; border: none; padding: .7rem;
           border-radius: 8px; cursor: pointer; font: inherit; }
  button:disabled { opacity: .6; cursor: default; }
  .muted { color: var(--muted); font-size: .9rem; }
  footer { text-align: center; color: var(--muted); padding: 2rem; font-size: .85rem; }

  .auth-box { display: flex; flex-direction: column; gap: .75rem; max-width: 320px; }
  .auth-toggle { display: flex; gap: 1rem; margin-bottom: .5rem; }
  .auth-toggle button { background: none; border: none; color: var(--muted); cursor: pointer;
                         padding: 0; font: inherit; border-bottom: 2px solid transparent;
                         border-radius: 0; }
  .auth-toggle button.active { color: var(--text); border-color: var(--accent); }
  .auth-user-badge { display: flex; align-items: center; gap: .75rem; color: var(--muted); }
  .auth-user-badge button { width: auto; padding: .4rem .8rem; font-size: .85rem; }
  .auth-error { color: #ff6b6b; font-size: .85rem; min-height: 1.2em; }

  .tabs { display: flex; gap: .5rem; margin-bottom: 1rem; }
  .tabs button { background: var(--surface); border: 1px solid var(--border); color: var(--muted);
                 width: auto; padding: .5rem 1rem; font-size: .9rem; }
  .tabs button.active { color: var(--text); border-color: var(--accent); }

  .pagination { display: flex; align-items: center; gap: .75rem; margin-top: 1rem; }
  .pagination button { width: auto; padding: .4rem .9rem; font-size: .85rem; }

  .inline-edit-form { display: flex; flex-direction: column; gap: .5rem; margin-top: .5rem; }
`;

const TOKEN_KEY = "access_token";
const getToken = () => localStorage.getItem(TOKEN_KEY);
const setToken = (t) => localStorage.setItem(TOKEN_KEY, t);
const clearToken = () => localStorage.removeItem(TOKEN_KEY);

function authHeaders() {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function injectStyles() {
  const style = document.createElement("style");
  style.textContent = STYLES;
  document.head.appendChild(style);
}

async function fetchJSON(url, options) {
  const res = await fetch(url, options);
  let body = null;
  try {
    body = await res.json();
  } catch {
    // No/invalid JSON body — leave body null, res.ok still tells us the outcome.
  }
  if (!res.ok) {
    const detail = body && body.detail;
    const message = Array.isArray(detail)
      ? detail.map((d) => d.msg).join(", ")
      : (detail || `Request failed: ${res.status}`);
    throw new Error(message);
  }
  return body;
}

function renderShell() {
  document.body.innerHTML = `
    <header>
      <h1>Hitesh Mondal</h1>
      <p>Software Engineer — building things with code</p>
    </header>
    <main>
      <section id="about">
        <h2>About</h2>
        <p class="muted"> DevOps/SRE/SDE</p>
      </section>
      <section id="auth">
        <h2>Account</h2>
        <div id="auth-container" class="muted">Loading…</div>
      </section>
      <section id="projects">
        <h2>Projects</h2>
        <div id="projects-tabs" class="tabs" style="display:none;">
          <button data-tab="all" class="active">All Projects</button>
          <button data-tab="mine">My Projects</button>
        </div>
        <div id="new-project-container"></div>
        <div id="projects-list" class="muted">Loading projects…</div>
        <div id="projects-pagination"></div>
      </section>
      <section id="admin-inbox" style="display:none;">
        <h2>Contact Inbox</h2>
        <p class="muted">Visible only to signed-in users.</p>
        <div id="inbox-list" class="muted">Loading…</div>
        <div id="inbox-pagination"></div>
      </section>
      <section id="contact">
        <h2>Contact</h2>
        <form id="contact-form">
          <input name="name" placeholder="Your name" required />
          <input name="email" type="email" placeholder="Your email" required />
          <textarea name="message" placeholder="Message" rows="4" required></textarea>
          <button type="submit">Send</button>
        </form>
        <p id="contact-status" class="muted"></p>
      </section>
    </main>
    <footer>Deployed via the platform &middot; ${new Date().getFullYear()}</footer>
  `;
}

// ---------------------------------------------------------------------------
// Projects: list (all / mine), create, inline edit, delete, pagination
// ---------------------------------------------------------------------------

const projectsState = {
  tab: "all", // "all" | "mine"
  page: 1,
  pageSize: 10,
  currentUser: null,
};

function projectCard(p, isOwner) {
  const editable = isOwner
    ? `
      <div class="card-actions">
        <button class="btn-secondary" data-action="edit" data-id="${p.id}">Edit</button>
        <button class="btn-danger" data-action="delete" data-id="${p.id}">Delete</button>
      </div>`
    : "";

  return `
    <div class="card" data-project-id="${p.id}">
      <div class="card-row">
        <div>
          <strong>${p.title}</strong>
          <p class="muted">${p.description || ""}</p>
          ${p.link ? `<a href="${p.link}" target="_blank" rel="noopener">${p.link}</a>` : ""}
        </div>
        ${editable}
      </div>
      <div class="edit-slot"></div>
    </div>
  `;
}

function wireProjectCardActions(listEl) {
  listEl.querySelectorAll('[data-action="delete"]').forEach((btn) => {
    btn.addEventListener("click", async () => {
      if (!confirm("Delete this project?")) return;
      try {
        await fetchJSON(`/api/v1/projects/${btn.dataset.id}`, {
          method: "DELETE",
          headers: authHeaders(),
        });
        loadProjects();
      } catch (err) {
        alert(err.message);
      }
    });
  });

  listEl.querySelectorAll('[data-action="edit"]').forEach((btn) => {
    btn.addEventListener("click", () => {
      const card = listEl.querySelector(`[data-project-id="${btn.dataset.id}"]`);
      const slot = card.querySelector(".edit-slot");
      if (slot.dataset.open === "true") {
        slot.innerHTML = "";
        slot.dataset.open = "false";
        return;
      }
      const title = card.querySelector("strong").textContent;
      const desc = card.querySelector("p.muted").textContent;
      const linkEl = card.querySelector("a");
      const link = linkEl ? linkEl.href : "";

      slot.dataset.open = "true";
      slot.innerHTML = `
        <form class="inline-edit-form" data-id="${btn.dataset.id}">
          <input name="title" value="${title.replace(/"/g, "&quot;")}" required />
          <textarea name="description" rows="2">${desc}</textarea>
          <input name="link" value="${link}" placeholder="https://..." />
          <button type="submit">Save</button>
        </form>
      `;
      slot.querySelector("form").addEventListener("submit", async (e) => {
        e.preventDefault();
        const data = Object.fromEntries(new FormData(e.target).entries());
        try {
          await fetchJSON(`/api/v1/projects/${btn.dataset.id}`, {
            method: "PATCH",
            headers: { "Content-Type": "application/json", ...authHeaders() },
            body: JSON.stringify(data),
          });
          loadProjects();
        } catch (err) {
          alert(err.message);
        }
      });
    });
  });
}

function renderPagination(container, page, totalPages, onChange) {
  if (totalPages <= 1) {
    container.innerHTML = "";
    return;
  }
  container.innerHTML = `
    <div class="pagination">
      <button ${page <= 1 ? "disabled" : ""} data-dir="prev">&larr; Prev</button>
      <span class="muted">Page ${page} of ${totalPages}</span>
      <button ${page >= totalPages ? "disabled" : ""} data-dir="next">Next &rarr;</button>
    </div>
  `;
  container.querySelector('[data-dir="prev"]')?.addEventListener("click", () => onChange(page - 1));
  container.querySelector('[data-dir="next"]')?.addEventListener("click", () => onChange(page + 1));
}

async function loadProjects() {
  const listEl = document.getElementById("projects-list");
  const paginationEl = document.getElementById("projects-pagination");
  const endpoint = projectsState.tab === "mine" ? "/api/v1/projects/mine" : "/api/v1/projects";

  try {
    const data = await fetchJSON(
      `${endpoint}?page=${projectsState.page}&page_size=${projectsState.pageSize}`,
      { headers: projectsState.tab === "mine" ? authHeaders() : {} }
    );

    if (!data.items.length) {
      listEl.textContent = projectsState.tab === "mine"
        ? "You haven't added any projects yet."
        : "No projects added yet.";
      paginationEl.innerHTML = "";
      return;
    }

    const currentUserId = projectsState.currentUser ? projectsState.currentUser.id : null;
    listEl.innerHTML = data.items
      .map((p) => projectCard(p, currentUserId !== null && p.owner_id === currentUserId))
      .join("");
    wireProjectCardActions(listEl);

    renderPagination(paginationEl, data.page, data.total_pages, (newPage) => {
      projectsState.page = newPage;
      loadProjects();
    });
  } catch (err) {
    listEl.textContent = "Could not load projects.";
    paginationEl.innerHTML = "";
    console.error(err);
  }
}

function renderProjectTabs(user) {
  const tabsEl = document.getElementById("projects-tabs");
  if (!user) {
    tabsEl.style.display = "none";
    projectsState.tab = "all";
    return;
  }
  tabsEl.style.display = "flex";
  tabsEl.querySelectorAll("button").forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.tab === projectsState.tab);
    btn.onclick = () => {
      projectsState.tab = btn.dataset.tab;
      projectsState.page = 1;
      renderProjectTabs(user);
      loadProjects();
    };
  });
}

function renderNewProjectForm(user) {
  const container = document.getElementById("new-project-container");
  if (!user) {
    container.innerHTML = "";
    return;
  }
  container.innerHTML = `
    <form id="new-project-form" class="card">
      <input name="title" placeholder="Project title" required />
      <textarea name="description" placeholder="Description" rows="2"></textarea>
      <input name="link" placeholder="https://..." />
      <button type="submit">Add project</button>
    </form>
  `;
  container.querySelector("#new-project-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const form = e.target;
    const button = form.querySelector("button");
    button.disabled = true;
    const data = Object.fromEntries(new FormData(form).entries());
    try {
      await fetchJSON("/api/v1/projects", {
        method: "POST",
        headers: { "Content-Type": "application/json", ...authHeaders() },
        body: JSON.stringify(data),
      });
      form.reset();
      loadProjects();
    } catch (err) {
      alert(err.message);
    } finally {
      button.disabled = false;
    }
  });
}

// ---------------------------------------------------------------------------
// Contact inbox (admin — any signed-in user)
// ---------------------------------------------------------------------------

const inboxState = { page: 1, pageSize: 10 };

async function loadInbox() {
  const listEl = document.getElementById("inbox-list");
  const paginationEl = document.getElementById("inbox-pagination");
  try {
    const data = await fetchJSON(
      `/api/v1/contact?page=${inboxState.page}&page_size=${inboxState.pageSize}`,
      { headers: authHeaders() }
    );
    if (!data.items.length) {
      listEl.textContent = "No messages yet.";
      paginationEl.innerHTML = "";
      return;
    }
    listEl.innerHTML = data.items
      .map(
        (m) => `
      <div class="card">
        <strong>${m.name}</strong> <span class="muted">&lt;${m.email}&gt;</span>
        <p>${m.message}</p>
        <p class="muted">${new Date(m.created_at).toLocaleString()}</p>
      </div>
    `
      )
      .join("");
    renderPagination(paginationEl, data.page, data.total_pages, (newPage) => {
      inboxState.page = newPage;
      loadInbox();
    });
  } catch (err) {
    listEl.textContent = "Could not load messages.";
    paginationEl.innerHTML = "";
    console.error(err);
  }
}

function renderAdminInboxSection(user) {
  const section = document.getElementById("admin-inbox");
  if (!user) {
    section.style.display = "none";
    return;
  }
  section.style.display = "block";
  inboxState.page = 1;
  loadInbox();
}

// ---------------------------------------------------------------------------
// Contact form
// ---------------------------------------------------------------------------

function wireContactForm() {
  const form = document.getElementById("contact-form");
  const status = document.getElementById("contact-status");

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const button = form.querySelector("button");
    button.disabled = true;
    status.textContent = "Sending…";

    const data = Object.fromEntries(new FormData(form).entries());

    try {
      await fetchJSON("/api/v1/contact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });
      status.textContent = "Message sent — thanks!";
      form.reset();
    } catch (err) {
      status.textContent = err.message || "Something went wrong. Try again later.";
      console.error(err);
    } finally {
      button.disabled = false;
    }
  });
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

async function fetchMe() {
  const token = getToken();
  if (!token) return null;
  try {
    const res = await fetch("/api/v1/auth/me", {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      clearToken();
      return null;
    }
    return res.json();
  } catch {
    return null;
  }
}

function onAuthStateChanged(user) {
  projectsState.currentUser = user;
  projectsState.tab = "all";
  projectsState.page = 1;
  renderProjectTabs(user);
  renderNewProjectForm(user);
  loadProjects();
  renderAdminInboxSection(user);
}

function renderAuthSection(container, user) {
  if (user) {
    container.innerHTML = `
      <div class="auth-user-badge">
        <span>Signed in as <strong>${user.email}</strong></span>
        <button id="logout-btn">Log out</button>
      </div>
    `;
    document.getElementById("logout-btn").addEventListener("click", () => {
      clearToken();
      renderAuthSection(container, null);
      onAuthStateChanged(null);
    });
    return;
  }

  let mode = "login"; // or "signup"

  function draw() {
    container.innerHTML = `
      <div class="auth-toggle">
        <button data-mode="login" class="${mode === "login" ? "active" : ""}">Log in</button>
        <button data-mode="signup" class="${mode === "signup" ? "active" : ""}">Sign up</button>
      </div>
      <form id="auth-form" class="auth-box">
        <input name="email" type="email" placeholder="Email" required />
        <input name="password" type="password" placeholder="Password" required minlength="8" />
        <button type="submit">${mode === "login" ? "Log in" : "Sign up"}</button>
        <p id="auth-error" class="auth-error"></p>
      </form>
    `;

    container.querySelectorAll(".auth-toggle button").forEach((btn) => {
      btn.addEventListener("click", () => {
        mode = btn.dataset.mode;
        draw();
      });
    });

    const form = document.getElementById("auth-form");
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const errorEl = document.getElementById("auth-error");
      errorEl.textContent = "";

      const submitBtn = form.querySelector("button[type=submit]");
      submitBtn.disabled = true;

      const data = Object.fromEntries(new FormData(form).entries());
      const endpoint = mode === "login" ? "/api/v1/auth/login" : "/api/v1/auth/signup";

      let res;
      try {
        res = await fetch(endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(data),
        });
      } catch (err) {
        errorEl.textContent = "Network error — check your connection and try again.";
        submitBtn.disabled = false;
        console.error(err);
        return;
      }

      let body = {};
      try {
        body = await res.json();
      } catch {
        errorEl.textContent = `Unexpected server response (HTTP ${res.status}). Check server logs.`;
        submitBtn.disabled = false;
        return;
      }

      if (!res.ok) {
        const detail = body.detail;
        errorEl.textContent = Array.isArray(detail)
          ? detail.map((d) => d.msg).join(", ")
          : (detail || `Something went wrong (HTTP ${res.status}).`);
        submitBtn.disabled = false;
        return;
      }

      setToken(body.access_token);
      const user = await fetchMe();
      renderAuthSection(container, user);
      onAuthStateChanged(user);
    });
  }

  draw();
}

function renderApp() {
  injectStyles();
  renderShell();
  wireContactForm();

  const authContainer = document.getElementById("auth-container");
  fetchMe().then((user) => {
    renderAuthSection(authContainer, user);
    onAuthStateChanged(user);
  });
}

document.addEventListener("DOMContentLoaded", renderApp);

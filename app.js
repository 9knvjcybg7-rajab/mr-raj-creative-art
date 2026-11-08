const courses = [
  {
    title: "Adobe Illustrator",
    category: "VECTOR & BRANDING",
    description: "Build bold vector artwork, thoughtful logos, and print-ready designs.",
    image: "https://images.unsplash.com/photo-1558655146-9f40138edfeb?auto=format&fit=crop&w=900&q=85",
    lessons: 10,
    level: "STARTER FRIENDLY",
    tag: "MOST POPULAR",
  },
  {
    title: "Adobe Photoshop",
    category: "PHOTO & COMPOSITION",
    description: "Edit, retouch, and transform images into eye-catching visual stories.",
    image: "https://images.unsplash.com/photo-1579783902614-a3fb3927b6a5?auto=format&fit=crop&w=900&q=85",
    lessons: 10,
    level: "STARTER FRIENDLY",
    tag: "MAKE AN IMPACT",
  },
  {
    title: "Procreate",
    category: "DIGITAL ILLUSTRATION",
    description: "Find your style with expressive digital drawing and painting.",
    image: "https://images.unsplash.com/photo-1577083552431-6e5fd01aa342?auto=format&fit=crop&w=900&q=85",
    lessons: 10,
    level: "STARTER FRIENDLY",
    tag: "CREATE YOUR WORLD",
  },
];

const courseGrid = document.querySelector("#course-grid");
const enrollDialog = document.querySelector("#enroll-dialog");
const enrollCourse = document.querySelector("#enroll-course");
const toast = document.querySelector(".toast");

function renderCourses() {
  courseGrid.innerHTML = courses.map((course, index) => `
    <article class="course-card">
      <div class="course-visual">
        <img src="${course.image}" alt="${course.title} course preview" loading="lazy" />
        <span class="course-number">0${index + 1} / 03</span>
        <span class="course-tag">${course.tag}</span>
      </div>
      <div class="course-details">
        <div class="course-topline"><span>${course.category}</span><span class="course-price">KSh 2,500</span></div>
        <h3>${course.title}</h3>
        <p>${course.description}</p>
        <div class="course-footer">
          <span class="course-meta"><strong>${course.lessons} lessons</strong> &nbsp;·&nbsp; ${course.level}</span>
          <button class="course-enroll" type="button" data-action="enroll" data-course="${course.title}" aria-label="Enrol in ${course.title}">↗</button>
        </div>
      </div>
    </article>
  `).join("");
}

function getSavedList(key) {
  try {
    const parsed = JSON.parse(localStorage.getItem(key) || "[]");
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    console.warn(`Could not read ${key} from local storage.`, error);
    return [];
  }
}

function saveEntry(key, entry) {
  const entries = getSavedList(key);
  entries.push({ ...entry, createdAt: new Date().toISOString() });
  localStorage.setItem(key, JSON.stringify(entries));
}

function showToast(message) {
  toast.textContent = message;
  toast.classList.add("visible");
  window.setTimeout(() => toast.classList.remove("visible"), 3200);
}

document.addEventListener("click", (event) => {
  const trigger = event.target.closest("[data-action='enroll']");
  if (!trigger) return;
  enrollCourse.value = trigger.dataset.course || courses[0].title;
  enrollDialog.showModal();
});

document.querySelector(".dialog-close").addEventListener("click", () => enrollDialog.close());
enrollDialog.addEventListener("click", (event) => {
  if (event.target === enrollDialog) enrollDialog.close();
});

document.querySelector("#enroll-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const values = Object.fromEntries(new FormData(form));
  saveEntry("mrca-enrolment-requests", values);
  form.reset();
  enrollCourse.value = courses[0].title;
  enrollDialog.close();
  showToast("Your enrolment request is saved on this device. Thank you!");
});

document.querySelector("#contact-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const form = event.currentTarget;
  const values = Object.fromEntries(new FormData(form));
  try {
    saveEntry("mrca-contact-enquiries", values);
    form.reset();
    form.querySelector(".form-status").textContent = "Thanks for reaching out — your message is saved on this device.";
  } catch (error) {
    console.error("Could not save your enquiry.", error);
    form.querySelector(".form-status").textContent = "We couldn’t save your message. Please email rajabhassan345@gmail.com.";
  }
});

const assistantPanel = document.querySelector("#assistant-panel");
const assistantLauncher = document.querySelector(".assistant-launcher");
const assistantMessages = document.querySelector("#assistant-messages");
const assistantInput = document.querySelector("#assistant-input");

function assistantAnswer(question) {
  const text = question.toLowerCase();
  if (/tutor|teacher|person|human|help me|talk to/.test(text)) {
    return "For one-to-one guidance, message Raj on WhatsApp at 0790 295 653 or email rajabhassan345@gmail.com. Use the “Talk to a tutor” link in the contact section to start a chat.";
  }
  if (/price|cost|fee|pay|payment|mpesa/.test(text)) {
    return "Each course costs KSh 2,500. The courses are Adobe Illustrator, Adobe Photoshop, and Procreate. Tap “Start learning” to request enrolment.";
  }
  if (/illustrator|logo|vector|brand/.test(text)) {
    return "Adobe Illustrator covers vector drawing, logos, typography, colour, and print design in 10 practical lessons. It’s starter friendly and costs KSh 2,500.";
  }
  if (/photoshop|photo|retouch|edit/.test(text)) {
    return "Adobe Photoshop covers layers, retouching, background removal, image manipulation, and visual design in 10 lessons. It’s starter friendly and costs KSh 2,500.";
  }
  if (/procreate|draw|paint|illustrat/.test(text)) {
    return "Procreate focuses on digital drawing, brushes, sketching, portraits, character design, and painting in 10 practical lessons. It costs KSh 2,500.";
  }
  if (/which|start|begin|choose|right course|recommend/.test(text)) {
    return "Choose Illustrator for logos and vector design, Photoshop for photo editing and visual composition, or Procreate for drawing and digital painting. All three are starter friendly and cost KSh 2,500. If you’re still unsure, Raj can help you choose.";
  }
  if (/lesson|course|learn|class|curriculum/.test(text)) {
    return "There are three courses: Adobe Illustrator, Adobe Photoshop, and Procreate. Each has 10 practical lessons and costs KSh 2,500. Visit the Courses section for details, or contact Raj for personal guidance.";
  }
  if (/contact|email|phone|number|whatsapp/.test(text)) {
    return "Reach Raj by phone or WhatsApp at 0790 295 653, or email rajabhassan345@gmail.com.";
  }
  return "I can answer questions about the three courses, lesson topics, and fees. For other questions, contact Raj at 0790 295 653 or rajabhassan345@gmail.com.";
}

function addAssistantMessage(text, kind) {
  const message = document.createElement("p");
  message.className = `assistant-message ${kind === "user" ? "assistant-user" : "assistant-reply"}`;
  message.textContent = text;
  assistantMessages.append(message);
  assistantMessages.scrollTop = assistantMessages.scrollHeight;
}

function askAssistant(question) {
  const trimmedQuestion = question.trim();
  if (!trimmedQuestion) return;
  addAssistantMessage(trimmedQuestion, "user");
  addAssistantMessage(assistantAnswer(trimmedQuestion), "reply");
}

assistantLauncher.addEventListener("click", () => {
  const isOpen = !assistantPanel.hidden;
  assistantPanel.hidden = isOpen;
  assistantLauncher.setAttribute("aria-expanded", String(!isOpen));
  if (!isOpen) assistantInput.focus();
});

document.querySelector(".assistant-close").addEventListener("click", () => {
  assistantPanel.hidden = true;
  assistantLauncher.setAttribute("aria-expanded", "false");
  assistantLauncher.focus();
});

document.querySelector("#assistant-form").addEventListener("submit", (event) => {
  event.preventDefault();
  askAssistant(assistantInput.value);
  assistantInput.value = "";
  assistantInput.focus();
});

document.querySelector(".assistant-prompts").addEventListener("click", (event) => {
  const prompt = event.target.closest("button");
  if (prompt) askAssistant(prompt.textContent);
});

const menuToggle = document.querySelector(".menu-toggle");
const mainNav = document.querySelector(".main-nav");
menuToggle.addEventListener("click", () => {
  const isExpanded = menuToggle.getAttribute("aria-expanded") === "true";
  menuToggle.setAttribute("aria-expanded", String(!isExpanded));
  menuToggle.setAttribute("aria-label", isExpanded ? "Open navigation" : "Close navigation");
  mainNav.classList.toggle("open", !isExpanded);
});
mainNav.addEventListener("click", (event) => {
  if (event.target.closest("a")) {
    mainNav.classList.remove("open");
    menuToggle.setAttribute("aria-expanded", "false");
    menuToggle.setAttribute("aria-label", "Open navigation");
  }
});

document.querySelector("#year").textContent = new Date().getFullYear();
renderCourses();

// 动态加载 Utterances 评论组件
function loadUtterances(container, issueTerm) {
  if (container.getAttribute('data-loaded')) return;
  var script = document.createElement('script');
  script.src = "https://utteranc.es/client.js";
  script.setAttribute("repo", "MAX-A-X/max-a-x.github.io");
  script.setAttribute("issue-term", issueTerm);
  script.setAttribute("theme", "github-dark");
  script.setAttribute("crossorigin", "anonymous");
  script.async = true;
  container.appendChild(script);
  container.setAttribute('data-loaded', 'true');
}

document.addEventListener("DOMContentLoaded", () => {

  class WorkManager {
    constructor() {
      // 作品卡片列表区域：只隐藏其中的 .grid-container
      this.workGrid = document.querySelector(".grid-container");
      // 作品详情区域
      this.workDetail = document.getElementById("work-detail");
      if (!this.workGrid || !this.workDetail) {
        console.error("❌ 错误：找不到作品列表或详情元素！");
        return;
      }
      this.setupEventListeners();
      this.checkInitialHash();
    }

    setupEventListeners() {
      console.log("绑定点击事件到作品卡片...");
      // 为每个作品卡片绑定点击事件
      document.querySelectorAll(".work-item").forEach(item => {
        item.addEventListener("click", () => {
          const workId = item.dataset.id;
          console.log(`作品卡片点击，ID: ${workId}`);
          this.showWorkDetail(workId);
        });
      });
      // 绑定返回按钮
      document.querySelectorAll(".back-to-list").forEach(button => {
        button.addEventListener("click", () => this.showWorkList());
      });
      // 监听 URL hash 变化
      window.addEventListener("hashchange", () => this.checkInitialHash());
    }

    checkInitialHash() {
      const workId = window.location.hash.substring(1);
      if (workId) {
        this.showWorkDetail(workId);
      } else {
        this.showWorkList();
      }
    }

    showWorkDetail(workId) {
      const work = document.getElementById(workId);
      if (!work) {
        console.error(`❌ 错误：找不到 ID 为 ${workId} 的作品`);
        return;
      }
      console.log(`✅ 显示作品: ${workId}`);
      // 隐藏作品卡片列表部分（grid-container），但保留标题及其他外围内容
      this.workGrid.classList.add("hidden");
      // 显示作品详情区域
      this.workDetail.classList.remove("hidden");
      // 隐藏所有作品详情内容
      document.querySelectorAll(".work-content").forEach(item => {
        item.classList.add("hidden");
      });
      // 显示对应的作品详情
      work.classList.remove("hidden");
      window.location.hash = workId;
      
      // 动态加载评论（如果未加载过）
      let container = work.querySelector(".utterances-container");
      if (container && !container.getAttribute('data-loaded')) {
         loadUtterances(container, workId);
      }
    }

    showWorkList() {
      // 显示作品卡片列表
      this.workGrid.classList.remove("hidden");
      // 隐藏作品详情区域
      this.workDetail.classList.add("hidden");
      history.pushState(null, "", "#");
    }
  }

  new WorkManager();
});

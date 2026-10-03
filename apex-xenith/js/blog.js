/*
class BlogManager {
  constructor() {
    this.blogList = document.getElementById('blog-list');
    this.blogDetail = document.getElementById('blog-detail');
    
    // 确保页面加载完成后再执行
    document.addEventListener('DOMContentLoaded', () => {
      this.init();
    });
  }

  init() {
    // 监听“阅读更多”按钮点击
    document.body.addEventListener('click', (e) => {
      if (e.target.classList.contains('read-more')) {
        e.preventDefault();
        const postId = e.target.getAttribute('data-post-id');
        this.showBlogDetail(postId);
      }
    });

    // 监听返回列表按钮
    document.body.addEventListener('click', (e) => {
      if (e.target.classList.contains('back-to-list')) {
        this.showBlogList();
      }
    });

    // 监听 Hash 变化
    window.addEventListener('hashchange', () => this.checkInitialHash());

    // 初次加载时检查 Hash
    this.checkInitialHash();
  }

showBlogDetail(postId) {
    const blogList = document.getElementById('blog-list');
    const blogDetail = document.getElementById('blog-detail');

    if (!blogList || !blogDetail) {
        console.error('❌ 错误：找不到博客列表或详情元素！');
        return;
    }

    blogList.classList.add('hidden');
    blogDetail.classList.remove('hidden');

    const post = document.getElementById(postId);
    if (post) {
        post.classList.remove('hidden');
        window.location.hash = postId;
    } else {
        console.warn(`⚠️ 未找到文章 ID: ${postId}`);
    }
}


    // 隐藏博客列表
    blogList.classList.add('hidden');

    // 显示博客详情
    blogDetail.classList.remove('hidden');

    // 隐藏所有文章内容
    const posts = document.querySelectorAll('.post-content');
    posts.forEach(post => post.classList.add('hidden'));

    // 显示指定的文章
    const targetPost = document.getElementById(postId);
    if (targetPost) {
        targetPost.classList.remove('hidden');
        // 更新 URL 哈希
        window.location.hash = postId;
    } else {
        console.warn(`未找到文章 ID: ${postId}`);
    }
}



  checkInitialHash() {
    const hash = window.location.hash.substring(1); // 去掉 #
    if (hash) {
      this.showBlogDetail(hash);
    } else {
      this.showBlogList();
    }
  }
}

function showBlogList() {
    document.getElementById('blog-list').classList.remove('hidden');
    document.getElementById('blog-detail').classList.add('hidden');
}

function backToList() {
    showBlogList();
    history.pushState("", document.title, window.location.pathname);
}


window.showBlogList = function () {
    console.log("返回博客列表");
    
    // 确保 HTML 元素存在
    let blogList = document.getElementById('blog-list');
    let blogDetail = document.getElementById('blog-detail');
    
    if (blogList && blogDetail) {
        blogList.classList.remove('hidden');
        blogDetail.classList.add('hidden');
    } else {
        console.error("blog-list 或 blog-detail 元素未找到");
    }
};

document.addEventListener('DOMContentLoaded', function() {
    const blogManager = new BlogManager();
    blogManager.showBlogList();
});

/*
document.addEventListener('DOMContentLoaded', function() {
    let backButtons = document.querySelectorAll('.back-to-list'); 
    backButtons.forEach(button => {
        button.addEventListener('click', function() {
            console.log("点击了返回列表");
            backToList();
        });
    });
});
*/
/* */
 /* 
document.querySelectorAll('.read-more').forEach(button => {
    button.addEventListener('click', function() {
        console.log("阅读更多按钮被点击了", this.dataset.postId);
    });
});

class BlogManager {
    constructor() {
        this.blogList = document.getElementById('blog-list');
        this.blogDetail = document.getElementById('blog-detail');
    }

    showBlogList() {
        if (this.blogList && this.blogDetail) {
            this.blogList.classList.remove('hidden');
            this.blogDetail.classList.add('hidden');
        } else {
            console.error('❌ 错误：找不到博客列表或详情元素！');
        }
    }
}

// 启动博客管理
new BlogManager();

*/










/*

class BlogManager {
  constructor() {
    this.blogList = document.querySelector(".blog-grid");
    this.blogDetail = document.getElementById("blog-detail");

    if (!this.blogList || !this.blogDetail) {
      console.error("❌ 错误：找不到博客列表或详情元素！");
      return;
    }

    this.init();
  }

  init() {
    console.log("✅ 博客管理器初始化");
    this.setupEventListeners();
    this.checkInitialHash();
  }

  setupEventListeners() {
    // 监听“阅读更多”按钮点击
    document.querySelectorAll(".read-more").forEach(button => {
      button.addEventListener("click", (event) => {
        event.preventDefault();
        const postId = event.target.dataset.postId;
        console.log(`📌 阅读更多按钮被点击了 ${postId}`);
        this.showBlogDetail(postId);
      });
    });

    // 监听返回列表按钮
    document.querySelectorAll(".back-to-list").forEach(button => {
      button.addEventListener("click", () => this.showBlogList());
    });
  }

  checkInitialHash() {
    if (window.location.hash) {
      const postId = window.location.hash.substring(1);
      this.showBlogDetail(postId);
    } else {
      this.showBlogList();
    }
  }

  showBlogDetail(postId) {
    const post = document.getElementById(postId);
    if (!post) {
      console.error(`❌ 错误：找不到 ID 为 ${postId} 的文章`);
      return;
    }

    this.blogList.style.display = "none";
    this.blogDetail.style.display = "block";

    document.querySelectorAll(".post-content").forEach(post => {
      post.classList.add("hidden");
    });

    post.classList.remove("hidden");
    window.location.hash = postId;
  }

  showBlogList() {
    this.blogList.style.display = "grid";
    this.blogDetail.style.display = "none";
    history.pushState(null, "", "#");
  }
}

// 初始化博客管理器
document.addEventListener("DOMContentLoaded", () => new BlogManager());
*/




// 动态加载 Utterances 评论组件
function loadUtterances(container, issueTerm) {
  if (container.getAttribute('data-loaded')) return;
  var script = document.createElement('script');
  script.src = "https://utteranc.es/client.js";
  script.setAttribute("repo", "MAX-A-X/max-a-x.github.io");
  script.setAttribute("issue-term", issueTerm);
  script.setAttribute("theme", "github-light");
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

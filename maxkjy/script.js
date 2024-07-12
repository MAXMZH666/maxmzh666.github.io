// 联系表单提交处理
document.getElementById('contactForm')?.addEventListener('submit', function(event) {
    event.preventDefault();
    alert('您的信息已提交！');
});

// 模拟应用安装的功能
document.querySelectorAll('.install-button').forEach(button => {
    button.addEventListener('click', function() {
        alert('应用已开始安装！');
    });
});

// 论坛发帖功能
const postForm = document.getElementById('postForm');
const posts = document.getElementById('posts');

// 加载帖子
function loadPosts() {
    const savedPosts = JSON.parse(localStorage.getItem('posts')) || [];
    posts.innerHTML = '';
    savedPosts.forEach(post => {
        const postElement = document.createElement('div');
        postElement.classList.add('post');
        postElement.innerHTML = `
            <h3>${post.title}</h3>
            <p>${post.content}</p>
        `;
        posts.appendChild(postElement);
    });
}

// 保存帖子
function savePost(title, content) {
    const savedPosts = JSON.parse(localStorage.getItem('posts')) || [];
    savedPosts.push({ title, content });
    localStorage.setItem('posts', JSON.stringify(savedPosts));
}

// 提交新帖子
postForm?.addEventListener('submit', function(event) {
    event.preventDefault();
    const title = document.getElementById('title').value;
    const content = document.getElementById('content').value;
    savePost(title, content);
    loadPosts();
    postForm.reset();
}

// 初始加载帖子
loadPosts();

function goBack() {
            window.history.back();
        }

// 模拟更新软件功能
// 更新软件按钮功能改为跳转到指定网站
function updateSoftware() {
    window.location.href = 'https://ldgs.lanzoul.com/b0zj27fkj';
}

// 模拟分享软件功能
function shareSoftware() {
    //const shareLink = "https://ldgs.lanzoul.com/b0zj27fkj 密码:1111"; // 假设的下载链接
    //const shareMessage = `分享MAX科技云应用：${shareLink}`;
    
    // 使用Navigator API进行分享（仅在支持的浏览器中有效）
    if (navigator.share) {
        navigator.share({
            title: 'MAX科技云',
            text: '分享MAX科技云应用',
            url: 'https://maxmzh666.github.io/project4.html'
        }).then(() => {
                    console.log('分享成功');
                }).catch((error) => {
                    console.error('分享失败:', error);
        });
    } else {
        // 不支持Navigator API的情况下，手动复制链接
        const tempInput = document.createElement('input');
        document.body.appendChild(tempInput);
        tempInput.value = shareLink;
        tempInput.select();
        document.execCommand('copy');
        document.body.removeChild(tempInput);
        alert('下载链接已复制到剪贴板：' + https://maxmzh666.github.io/project4.html);
    }
}

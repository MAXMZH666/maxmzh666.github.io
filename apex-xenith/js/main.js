// 注册 Service Worker
if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('sw.js').then(reg => {
        console.log("Service Worker 注册成功，作用域：", reg.scope);
        
        // 监听更新
        reg.onupdatefound = () => {
            const newSW = reg.installing;
            newSW.onstatechange = () => {
                if (newSW.state === 'installed' && navigator.serviceWorker.controller) {
                    alert("新版本可用，刷新页面以更新！");
                    location.reload(); // 刷新页面以加载新版本
                }
            };
        };
    }).catch(error => console.error("Service Worker 注册失败:", error));
}

// 手动检查新 APK 版本
function checkForUpdate() {
    fetch('/version.json')
        .then(response => response.json())
        .then(data => {
            const latestVersion = data.version;
            const apkURL = data.apk_url;
            const currentVersion = localStorage.getItem('app_version');

            if (currentVersion !== latestVersion) {
                if (confirm("发现新版本，是否下载更新？")) {
                    window.location.href = apkURL; // 跳转到新 APK 下载地址
                }
                localStorage.setItem('app_version', latestVersion);
            } else {
                alert("当前已经是最新版本！");
            }
        })
        .catch(error => console.error("检查更新失败:", error));
}

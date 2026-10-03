async function checkForUpdate() {
    const latestVersion = await fetch("https://raw.githubusercontent.com/max-a-x/github.io/main/version.json")
        .then(res => res.json())
        .then(data => data.version);

    const currentVersion = localStorage.getItem("app_version") || "1.0.0";

    if (latestVersion !== currentVersion) {
        if (confirm("发现新版本 " + latestVersion + "，是否下载更新？")) {
            window.location.href = "https://github.com/max-a-x/github.io/releases/latest/download/app-release.apk";
        }
    }
}

checkForUpdate();

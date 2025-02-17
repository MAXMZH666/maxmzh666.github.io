// viewport.js

// 检查页面中是否已经有视口 meta 标签
if (!document.querySelector('meta[name="viewport"]')) {
  // 创建新的 meta 标签
  const metaTag = document.createElement('meta');
  metaTag.name = 'viewport';
  metaTag.content = 'width=device-width, initial-scale=1.0';  // 设置视口内容

  // 将新创建的 meta 标签添加到 <head> 部分
  document.head.appendChild(metaTag);
}

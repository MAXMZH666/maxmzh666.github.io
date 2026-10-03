class SearchManager {
  constructor() {
    this.searchInput = document.querySelector('.search-input');
    this.searchResults = document.querySelector('.search-results');
    this.currentMatches = [];
    this.init();
  }

  init() {
    this.searchInput.addEventListener('input', this.debounce(this.handleSearch, 300));
    document.addEventListener('click', this.handleClickOutside.bind(this));
  }

  handleSearch = () => {
    const query = this.searchInput.value.trim();
    this.searchResults.innerHTML = '';
    
    if (!query) {
      this.searchResults.style.display = 'none';
      return;
    }

    this.currentMatches = this.searchContent(query);
    this.displayResults();
  }

  searchContent(query) {
    const regex = new RegExp(this.escapeRegExp(query), 'gi');
    const nodes = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: node => {
          if (node.parentNode.classList.contains('search-container')) {
            return NodeFilter.FILTER_REJECT;
          }
          return regex.test(node.textContent) ? 
            NodeFilter.FILTER_ACCEPT : 
            NodeFilter.FILTER_REJECT;
        }
      }
    );

    const matches = [];
    let currentNode;
    while ((currentNode = nodes.nextNode())) {
      const content = currentNode.textContent;
      const matches = [...content.matchAll(regex)];
      
      matches.forEach(match => {
        const startIndex = match.index;
        const endIndex = startIndex + match[0].length;
        
        const span = document.createElement('span');
        span.innerHTML = content.substring(0, startIndex) + 
          `<mark class="mark">${content.substring(startIndex, endIndex)}</mark>` + 
          content.substring(endIndex);
        
        const range = document.createRange();
        range.selectNodeContents(currentNode);
        
        const parent = currentNode.parentNode;
        parent.replaceChild(span, currentNode);
        
        matches.push({
          element: span.querySelector('mark'),
          originalText: currentNode
        });
      });
    }

    return matches;
  }

  displayResults() {
    this.searchResults.style.display = 'block';
    
    this.currentMatches.forEach((match, index) => {
      const context = this.getTextContext(match.originalText, 50);
      const resultItem = document.createElement('div');
      resultItem.className = 'search-result-item';
      resultItem.innerHTML = `
        <div class="result-context">${context}</div>
      `;
      
      resultItem.addEventListener('click', () => {
        match.element.scrollIntoView({
          behavior: 'smooth',
          block: 'center'
        });
        match.element.animate([
          { backgroundColor: 'rgba(255,235,59,0.3)' },
          { backgroundColor: 'rgba(255,235,59,0.6)' },
          { backgroundColor: 'rgba(255,235,59,0.3)' }
        ], {
          duration: 1000,
          iterations: 2
        });
      });

      this.searchResults.appendChild(resultItem);
    });
  }

  getTextContext(node, charsAround) {
    const fullText = node.textContent;
    const matchText = node.parentNode.querySelector('mark').textContent;
    const index = fullText.indexOf(matchText);
    
    const start = Math.max(0, index - charsAround);
    const end = Math.min(fullText.length, index + matchText.length + charsAround);
    
    return (start > 0 ? '...' : '') + 
           fullText.substring(start, end).replace(
             new RegExp(this.escapeRegExp(matchText), 'gi'), 
             '<strong>$&</strong>'
           ) + 
           (end < fullText.length ? '...' : '');
  }

  escapeRegExp(string) {
    return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }

  debounce(func, wait) {
    let timeout;
    return (...args) => {
      clearTimeout(timeout);
      timeout = setTimeout(() => func.apply(this, args), wait);
    };
  }

  handleClickOutside(e) {
    if (!this.searchContainer.contains(e.target)) {
      this.searchResults.style.display = 'none';
    }
  }
}

// 初始化
document.addEventListener('DOMContentLoaded', () => {
  new SearchManager();
});

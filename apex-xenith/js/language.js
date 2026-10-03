class LanguageManager {
  constructor() {
    this.currentLang = localStorage.getItem('lang') || 'zh-CN';
    this.elements = document.querySelectorAll('[data-i18n]');
    this.init();
  }

  async init() {
    await this.loadLanguage(this.currentLang);
    this.setupSwitcher();
  }

  async loadLanguage(lang) {
    try {
      const response = await fetch(`/lang/${lang}.json`);
      this.translations = await response.json();
      this.applyTranslations();
      localStorage.setItem('lang', lang);
      document.documentElement.lang = lang;
    } catch (error) {
      console.error('Error loading language file:', error);
    }
  }

  applyTranslations() {
    this.elements.forEach(element => {
      const keys = element.dataset.i18n.split('.');
      let value = this.translations;
      
      keys.forEach(key => {
        value = value[key];
      });

      if (element.tagName === 'INPUT' && element.placeholder) {
        element.placeholder = value;
      } else {
        element.textContent = value;
      }
    });
  }

  setupSwitcher() {
    document.querySelectorAll('.language-switcher button').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.lang === this.currentLang);
      
      btn.addEventListener('click', () => {
        if (btn.dataset.lang !== this.currentLang) {
          this.currentLang = btn.dataset.lang;
          this.loadLanguage(this.currentLang);
          document.querySelectorAll('.language-switcher button').forEach(b => {
            b.classList.toggle('active', b.dataset.lang === this.currentLang);
          });
        }
      });
    });
  }
}

// 初始化
document.addEventListener('DOMContentLoaded', () => {
  new LanguageManager();
});

localizeDates() {
  document.querySelectorAll('[data-i18n-date]').forEach(element => {
    const date = new Date(element.dataset.i18nDate);
    const options = { 
      year: 'numeric', 
      month: 'long', 
      day: 'numeric' 
    };
    
    element.textContent = this.currentLang === 'en-US' 
      ? date.toLocaleDateString('en-US', options)
      : date.toLocaleDateString('zh-CN', options);
  });
}

// 在applyTranslations方法最后调用
this.localizeDates();
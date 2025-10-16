// 运行时配置文件 - 替代 .env 文件功能
// Runtime Configuration - Replace .env file functionality

window.APP_CONFIG = {
  // Node.js 环境 (Node.js Environment)
  NODE_ENV: 'development',
  
  // 项目名称 (Project Name)
  PROJECT_NAME: 'mcp-market',
  
  // 项目版本 (Project Version)
  PROJECT_VERSION: '1.0.0',
  
  // 运行环境 (Runtime Environment)
  RUNTIME_ENV: 'dev',
  
  // 服务端口号 (Server Port)
  PORT: 3000,
  
  // 项目基础路径 (Project Base Path)
  BASE_PATH: '/',
  
  // 是否启用Mock数据 (Enable Mock Data)
  MOCK_ENABLED: false,
  
  // 调试模式 (Debug Mode)
  DEBUG_MODE: true,
  
  // 日志级别 (Log Level: debug, info, warn, error)
  LOG_LEVEL: 'info',
  
  // 后端API地址 (Backend API Host)
  API_HOST: 'http://134.175.7.229',
  
  // 后端API路径前缀 (Backend API Path Prefix)
  API_PATH_PREFIX: '/api',
  
  // 扩展配置 (Extended Configuration)
  // 可以根据不同环境动态修改这些配置
  FEATURES: {
    // 功能开关
    ENABLE_ANALYTICS: true,
    ENABLE_ERROR_REPORTING: true,
    ENABLE_PERFORMANCE_MONITORING: false
  },
  
  // 主题配置 (Theme Configuration)
  THEME: {
    PRIMARY_COLOR: '#1890ff',
    DARK_MODE: false
  },
  
  // 获取配置的辅助方法
  get: function(key, defaultValue = null) {
    const keys = key.split('.');
    let value = this;
    
    for (const k of keys) {
      if (value && typeof value === 'object' && k in value) {
        value = value[k];
      } else {
        return defaultValue;
      }
    }
    
    return value;
  },
  
  // 检查功能是否启用
  isFeatureEnabled: function(featureName) {
    return this.get(`FEATURES.${featureName}`, false);
  },
  
  // 获取完整的API URL
  getApiUrl: function(path = '') {
    const host = this.API_HOST.replace(/\/$/, '');
    const prefix = this.API_PATH_PREFIX.replace(/^\/?/, '/').replace(/\/$/, '');
    const cleanPath = path.replace(/^\//, '');
    return `${host}${prefix}${cleanPath ? '/' + cleanPath : ''}`;
  }
};

// 环境特定配置覆盖 (Environment-specific overrides)
if (window.APP_CONFIG.RUNTIME_ENV === 'production') {
  // 生产环境配置
  window.APP_CONFIG.DEBUG_MODE = false;
  window.APP_CONFIG.LOG_LEVEL = 'error';
  window.APP_CONFIG.FEATURES.ENABLE_PERFORMANCE_MONITORING = true;
} else if (window.APP_CONFIG.RUNTIME_ENV === 'test') {
  // 测试环境配置
  window.APP_CONFIG.MOCK_ENABLED = true;
  window.APP_CONFIG.API_HOST = 'http://localhost:8081';
}

// 导出配置供模块使用 (Export for module usage)
if (typeof module !== 'undefined' && module.exports) {
  module.exports = window.APP_CONFIG;
}

console.log('Runtime configuration loaded:', window.APP_CONFIG.RUNTIME_ENV);
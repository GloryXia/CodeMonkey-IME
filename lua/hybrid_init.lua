-- ============================================================
-- hybrid_init.lua — Hybrid IME 入口文件
-- 注册所有 Lua 组件到 Rime 引擎
-- ============================================================

-- 加载模块
local hybrid_processor_mod     = require("hybrid_processor")
local punctuation_processor_mod = require("punctuation_processor")
local auto_space_filter_mod    = require("auto_space_filter")
local hybrid_filter_mod        = require("hybrid_filter")

-- ============================================================
-- 注册 Processor（按键处理器）
-- ============================================================

-- 混合输入状态管理处理器
hybrid_processor = hybrid_processor_mod.func
hybrid_processor_init = hybrid_processor_mod.init

-- 标点智能决策处理器
punctuation_processor = punctuation_processor_mod.func
punctuation_processor_init = punctuation_processor_mod.init

-- ============================================================
-- 注册 Filter（候选过滤器）
-- ============================================================

-- 混合候选重排
hybrid_filter = hybrid_filter_mod.func
hybrid_filter_init = hybrid_filter_mod.init

-- 自动空格
auto_space_filter = auto_space_filter_mod.func
auto_space_filter_init = auto_space_filter_mod.init

-- ============================================================
-- hybrid_init.lua — 程序猿输入法 入口文件
-- 注册所有 Lua 组件到 Rime 引擎
-- ============================================================

-- 加载模块
local hybrid_processor_mod     = require("hybrid_processor")
local punctuation_processor_mod = require("punctuation_processor")
local auto_space_filter_mod    = require("auto_space_filter")
local candidate_rerank_filter_mod = require("candidate_rerank_filter")
local hybrid_filter_mod        = require("hybrid_filter")

-- ============================================================
-- 注册 Processor（按键处理器）
-- ============================================================

-- 混合输入状态管理处理器
hybrid_processor = hybrid_processor_mod.func
hybrid_processor_init = hybrid_processor_mod.init
hybrid_processor_fini = hybrid_processor_mod.fini

-- 标点智能决策处理器
punctuation_processor = punctuation_processor_mod.func
punctuation_processor_init = punctuation_processor_mod.init
punctuation_processor_fini = punctuation_processor_mod.fini

-- ============================================================
-- 注册 Filter（候选过滤器）
-- ============================================================

-- 混合候选重排
hybrid_filter = hybrid_filter_mod.func
hybrid_filter_init = hybrid_filter_mod.init
hybrid_filter_fini = hybrid_filter_mod.fini

-- Phase 2 保守版候选重排
candidate_rerank_filter = candidate_rerank_filter_mod.func
candidate_rerank_filter_init = candidate_rerank_filter_mod.init
candidate_rerank_filter_fini = candidate_rerank_filter_mod.fini

-- 自动空格
auto_space_filter = auto_space_filter_mod.func
auto_space_filter_init = auto_space_filter_mod.init
auto_space_filter_fini = auto_space_filter_mod.fini

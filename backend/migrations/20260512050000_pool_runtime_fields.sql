-- +goose Up
-- +goose StatementBegin
--
-- 给 pool_gpt / pool_grok 补 gateway runtime 字段。
--
-- 背景：account 表过去同时承担「号池存储」+「runtime 调度状态」两个角色，
--       但号池管理已经分到 pool_gpt / pool_grok / pool_adobe 里去了，
--       account 表里现在 0 行。
--       为了让 ChatService / GenerationService / AccountPool 这些「runtime
--       调度」组件直接从号池表里取号，需要把 account 表上承担 runtime 用途
--       的字段补到 pool_gpt 和 pool_grok 上。
--
-- 这次只加列，不动旧表，不改语义，零破坏性。
--

-- pool_gpt 补 runtime 字段
ALTER TABLE `pool_gpt`
  ADD COLUMN `proxy_id`              BIGINT UNSIGNED DEFAULT NULL                                              COMMENT '出口代理 proxy.id（可空 = 直连）'                                       AFTER `oauth_client_id`,
  ADD COLUMN `base_url`              VARCHAR(255)    DEFAULT NULL                                              COMMENT '自定义上游 base_url（可空 = 走 api.openai.com）'                       AFTER `proxy_id`,
  ADD COLUMN `model_whitelist`       JSON            DEFAULT NULL                                              COMMENT 'JSON 数组：允许使用本号的 model_code 列表（NULL = 不限制）'              AFTER `base_url`,
  ADD COLUMN `weight`                INT             NOT NULL DEFAULT 10                                       COMMENT 'weighted_rr 权重，0/负数 = 1'                                            AFTER `model_whitelist`,
  ADD COLUMN `rpm_limit`             INT             NOT NULL DEFAULT 0                                        COMMENT '每分钟最大调度数（0 = 不限）'                                            AFTER `weight`,
  ADD COLUMN `tpm_limit`             INT             NOT NULL DEFAULT 0                                        COMMENT '每分钟最大 token 数（0 = 不限）'                                         AFTER `rpm_limit`,
  ADD COLUMN `daily_quota`           INT             NOT NULL DEFAULT 0                                        COMMENT '日配额（0 = 不限）'                                                      AFTER `tpm_limit`,
  ADD COLUMN `monthly_quota`         INT             NOT NULL DEFAULT 0                                        COMMENT '月配额（0 = 不限）'                                                      AFTER `daily_quota`,
  ADD COLUMN `cooldown_until`        DATETIME(3)     DEFAULT NULL                                              COMMENT '熔断到期时间（NULL = 不熔断）'                                            AFTER `monthly_quota`,
  ADD COLUMN `last_test_at`          DATETIME(3)     DEFAULT NULL                                              COMMENT '最近一次健康探活时间'                                                    AFTER `cooldown_until`,
  ADD COLUMN `last_test_status`      TINYINT         NOT NULL DEFAULT 0                                        COMMENT '0未测 1OK 2失败'                                                         AFTER `last_test_at`,
  ADD COLUMN `last_test_latency_ms`  INT             NOT NULL DEFAULT 0                                        COMMENT '最近一次探活延迟(ms)'                                                    AFTER `last_test_status`,
  ADD COLUMN `last_test_error`       VARCHAR(255)    DEFAULT NULL                                              COMMENT '最近一次探活失败原因'                                                    AFTER `last_test_latency_ms`,
  ADD COLUMN `success_count`         BIGINT UNSIGNED NOT NULL DEFAULT 0                                        COMMENT '累计成功调度次数（gateway）'                                              AFTER `last_test_error`,
  ADD COLUMN `remark`                VARCHAR(255)    DEFAULT NULL                                              COMMENT '管理员备注（gateway 用，不与 notes 冲突）'                                AFTER `success_count`,
  ADD KEY `idx_pool_gpt_status_cd`   (`status`, `cooldown_until`),
  ADD KEY `idx_pool_gpt_test`        (`last_test_status`);

-- pool_grok 补 runtime 字段 + 补 gateway 用的 status / last_used_at / last_refresh_at
ALTER TABLE `pool_grok`
  ADD COLUMN `status`                VARCHAR(32)     NOT NULL DEFAULT 'valid'                                  COMMENT 'gateway 调度状态 valid / invalid / disabled / cooldown'                  AFTER `account_type`,
  ADD COLUMN `expires_at`            DATETIME(3)     DEFAULT NULL                                              COMMENT 'sso 失效时间（NULL = 未知 / 不跟踪）'                                   AFTER `status`,
  ADD COLUMN `last_refresh_at`       DATETIME(3)     DEFAULT NULL                                              COMMENT '最近一次刷新 SSO 的时间'                                                  AFTER `last_checked_at`,
  ADD COLUMN `last_used_at`          DATETIME(3)     DEFAULT NULL                                              COMMENT '最近一次被 gateway 调度的时间'                                            AFTER `last_refresh_at`,
  ADD COLUMN `error_message`         VARCHAR(500)    DEFAULT NULL                                              COMMENT 'gateway 最近一次失败原因（与 trial_error 区分：那个是开通试用阶段的）'  AFTER `last_used_at`,
  ADD COLUMN `proxy_id`              BIGINT UNSIGNED DEFAULT NULL                                              COMMENT '出口代理 proxy.id（可空 = 直连）'                                       AFTER `error_message`,
  ADD COLUMN `base_url`              VARCHAR(255)    DEFAULT NULL                                              COMMENT '自定义上游 base_url（可空 = 默认 grok）'                                AFTER `proxy_id`,
  ADD COLUMN `model_whitelist`       JSON            DEFAULT NULL                                              COMMENT 'JSON 数组：允许使用本号的 model_code 列表'                               AFTER `base_url`,
  ADD COLUMN `weight`                INT             NOT NULL DEFAULT 10                                       COMMENT 'weighted_rr 权重'                                                        AFTER `model_whitelist`,
  ADD COLUMN `rpm_limit`             INT             NOT NULL DEFAULT 0                                        COMMENT '每分钟最大调度数'                                                        AFTER `weight`,
  ADD COLUMN `tpm_limit`             INT             NOT NULL DEFAULT 0                                        COMMENT '每分钟最大 token 数'                                                     AFTER `rpm_limit`,
  ADD COLUMN `daily_quota`           INT             NOT NULL DEFAULT 0                                        COMMENT '日配额'                                                                  AFTER `tpm_limit`,
  ADD COLUMN `monthly_quota`         INT             NOT NULL DEFAULT 0                                        COMMENT '月配额'                                                                  AFTER `daily_quota`,
  ADD COLUMN `cooldown_until`        DATETIME(3)     DEFAULT NULL                                              COMMENT '熔断到期时间'                                                            AFTER `monthly_quota`,
  ADD COLUMN `last_test_at`          DATETIME(3)     DEFAULT NULL                                              COMMENT '最近一次健康探活时间'                                                    AFTER `cooldown_until`,
  ADD COLUMN `last_test_status`      TINYINT         NOT NULL DEFAULT 0                                        COMMENT '0未测 1OK 2失败'                                                         AFTER `last_test_at`,
  ADD COLUMN `last_test_latency_ms`  INT             NOT NULL DEFAULT 0                                        COMMENT '最近一次探活延迟(ms)'                                                    AFTER `last_test_status`,
  ADD COLUMN `last_test_error`       VARCHAR(255)    DEFAULT NULL                                              COMMENT '最近一次探活失败原因'                                                    AFTER `last_test_latency_ms`,
  ADD COLUMN `success_count`         BIGINT UNSIGNED NOT NULL DEFAULT 0                                        COMMENT '累计成功调度次数'                                                        AFTER `last_test_error`,
  ADD COLUMN `remark`                VARCHAR(255)    DEFAULT NULL                                              COMMENT '管理员备注'                                                              AFTER `success_count`,
  ADD KEY `idx_pool_grok_status_cd`  (`status`, `cooldown_until`),
  ADD KEY `idx_pool_grok_test`       (`last_test_status`);

-- 把已有 pool_grok 行的 status 根据 trial_status 初始化一下：
--   trial_status = active  -> status = valid
--   trial_status = expired -> status = invalid
--   其它                   -> status = disabled
UPDATE `pool_grok`
SET `status` = CASE
  WHEN `trial_status` = 'active'  THEN 'valid'
  WHEN `trial_status` = 'expired' THEN 'invalid'
  ELSE                                  'disabled'
END
WHERE `deleted_at` IS NULL;

-- +goose StatementEnd

-- +goose Down
ALTER TABLE `pool_gpt`
  DROP KEY `idx_pool_gpt_status_cd`,
  DROP KEY `idx_pool_gpt_test`,
  DROP COLUMN `remark`,
  DROP COLUMN `success_count`,
  DROP COLUMN `last_test_error`,
  DROP COLUMN `last_test_latency_ms`,
  DROP COLUMN `last_test_status`,
  DROP COLUMN `last_test_at`,
  DROP COLUMN `cooldown_until`,
  DROP COLUMN `monthly_quota`,
  DROP COLUMN `daily_quota`,
  DROP COLUMN `tpm_limit`,
  DROP COLUMN `rpm_limit`,
  DROP COLUMN `weight`,
  DROP COLUMN `model_whitelist`,
  DROP COLUMN `base_url`,
  DROP COLUMN `proxy_id`;

ALTER TABLE `pool_grok`
  DROP KEY `idx_pool_grok_status_cd`,
  DROP KEY `idx_pool_grok_test`,
  DROP COLUMN `remark`,
  DROP COLUMN `success_count`,
  DROP COLUMN `last_test_error`,
  DROP COLUMN `last_test_latency_ms`,
  DROP COLUMN `last_test_status`,
  DROP COLUMN `last_test_at`,
  DROP COLUMN `cooldown_until`,
  DROP COLUMN `monthly_quota`,
  DROP COLUMN `daily_quota`,
  DROP COLUMN `tpm_limit`,
  DROP COLUMN `rpm_limit`,
  DROP COLUMN `weight`,
  DROP COLUMN `model_whitelist`,
  DROP COLUMN `base_url`,
  DROP COLUMN `proxy_id`,
  DROP COLUMN `error_message`,
  DROP COLUMN `last_used_at`,
  DROP COLUMN `last_refresh_at`,
  DROP COLUMN `expires_at`,
  DROP COLUMN `status`;

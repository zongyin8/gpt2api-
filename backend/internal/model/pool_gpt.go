package model

import (
	"encoding/json"
	"time"
)

// PoolGpt 状态。
const (
	GPTStatusValid    = "valid"
	GPTStatusInvalid  = "invalid"
	GPTStatusDisabled = "disabled"
	GPTStatusCooldown = "cooldown"
)

// PoolGpt GPT 号池实体。表 `pool_gpt`。
type PoolGpt struct {
	ID              uint64     `gorm:"primaryKey;column:id" json:"id"`
	Email           string     `gorm:"column:email;size:255;not null" json:"email"`
	PasswordEnc     []byte     `gorm:"column:password_enc;type:blob" json:"-"`
	AccessTokenEnc  []byte     `gorm:"column:access_token_enc;type:blob" json:"-"`
	RefreshTokenEnc []byte     `gorm:"column:refresh_token_enc;type:blob" json:"-"`
	IDTokenEnc      []byte     `gorm:"column:id_token_enc;type:blob" json:"-"`
	APIKeyEnc       []byte     `gorm:"column:api_key_enc;type:blob" json:"-"`
	OAuthIssuer     *string    `gorm:"column:oauth_issuer;size:255" json:"oauth_issuer,omitempty"`
	OAuthClientID   *string    `gorm:"column:oauth_client_id;size:128" json:"oauth_client_id,omitempty"`

	// 账号画像 + 配额（来自 wham/usage + JWT 解码，由 RefreshOne 维护）
	PlanType                    *string    `gorm:"column:plan_type;size:32" json:"plan_type,omitempty"`
	ChatGPTAccountID            *string    `gorm:"column:chatgpt_account_id;size:64" json:"chatgpt_account_id,omitempty"`
	QuotaPrimaryUsedPercent     *float64   `gorm:"column:quota_primary_used_percent;type:decimal(5,2)" json:"quota_primary_used_percent,omitempty"`
	QuotaPrimaryResetAt         *time.Time `gorm:"column:quota_primary_reset_at" json:"quota_primary_reset_at,omitempty"`
	QuotaSecondaryUsedPercent   *float64   `gorm:"column:quota_secondary_used_percent;type:decimal(5,2)" json:"quota_secondary_used_percent,omitempty"`
	QuotaSecondaryResetAt       *time.Time `gorm:"column:quota_secondary_reset_at" json:"quota_secondary_reset_at,omitempty"`
	QuotaCodeReviewUsedPercent  *float64   `gorm:"column:quota_code_review_used_percent;type:decimal(5,2)" json:"quota_code_review_used_percent,omitempty"`
	LastQuotaCheckAt            *time.Time `gorm:"column:last_quota_check_at" json:"last_quota_check_at,omitempty"`

	// Gateway runtime 字段（与 account 表语义对齐，承担调度状态）。
	ProxyID            *uint64    `gorm:"column:proxy_id" json:"proxy_id,omitempty"`
	BaseURL            *string    `gorm:"column:base_url;size:255" json:"base_url,omitempty"`
	ModelWhitelist     *string    `gorm:"column:model_whitelist;type:json" json:"model_whitelist,omitempty"`
	Weight             int        `gorm:"column:weight;not null;default:10" json:"weight"`
	RPMLimit           int        `gorm:"column:rpm_limit;not null;default:0" json:"rpm_limit"`
	TPMLimit           int        `gorm:"column:tpm_limit;not null;default:0" json:"tpm_limit"`
	DailyQuota         int        `gorm:"column:daily_quota;not null;default:0" json:"daily_quota"`
	MonthlyQuota       int        `gorm:"column:monthly_quota;not null;default:0" json:"monthly_quota"`
	CooldownUntil      *time.Time `gorm:"column:cooldown_until" json:"cooldown_until,omitempty"`
	LastTestAt         *time.Time `gorm:"column:last_test_at" json:"last_test_at,omitempty"`
	LastTestStatus     int8       `gorm:"column:last_test_status;not null;default:0" json:"last_test_status"`
	LastTestLatencyMs  int        `gorm:"column:last_test_latency_ms;not null;default:0" json:"last_test_latency_ms"`
	LastTestError      *string    `gorm:"column:last_test_error;size:255" json:"last_test_error,omitempty"`
	SuccessCount       uint64     `gorm:"column:success_count;not null;default:0" json:"success_count"`
	Remark             *string    `gorm:"column:remark;size:255" json:"remark,omitempty"`

	Status        string     `gorm:"column:status;size:32;not null;default:valid" json:"status"`
	ExpiresAt     *time.Time `gorm:"column:expires_at" json:"expires_at,omitempty"`
	LastCheckedAt *time.Time `gorm:"column:last_checked_at" json:"last_checked_at,omitempty"`
	LastRefreshAt *time.Time `gorm:"column:last_refresh_at" json:"last_refresh_at,omitempty"`
	LastUsedAt    *time.Time `gorm:"column:last_used_at" json:"last_used_at,omitempty"`
	FailureCount  int        `gorm:"column:failure_count;not null;default:0" json:"failure_count"`
	ErrorMessage  *string    `gorm:"column:error_message;size:500" json:"error_message,omitempty"`
	Notes         *string    `gorm:"column:notes;size:500" json:"notes,omitempty"`
	RegisteredAt  time.Time  `gorm:"column:registered_at;autoCreateTime" json:"registered_at"`
	CreatedAt     time.Time  `gorm:"column:created_at;autoCreateTime" json:"created_at"`
	UpdatedAt     time.Time  `gorm:"column:updated_at;autoUpdateTime" json:"updated_at"`
	DeletedAt     *time.Time `gorm:"column:deleted_at;index" json:"-"`
}

// TableName 表名。
func (PoolGpt) TableName() string { return "pool_gpt" }

// ToAccount 把 pool_gpt 行装配成 gateway 调度用的 *Account DTO。
//
// 调用方（AccountRepo / AccountPool）从 pool_gpt 取出来后调一下，
// 让原本读 account 表的 chat_service / generation_service / account_test_service
// 几乎不需要改 —— acc 还是 *Account，下游字段访问保持原样。
//
// Pool_gpt.status 与 account.Status (int8) 的语义映射：
//   - valid    -> AccountStatusEnabled
//   - invalid  -> AccountStatusBroken（拿不动了）
//   - disabled -> AccountStatusDisabled（管理员关掉了）
//   - cooldown -> AccountStatusBroken + 走 CooldownUntil
//
// AccountID 即 pool_gpt.id。注意 ID 在 pool_gpt 与 pool_grok 是独立序列，
// AccountPool 已经按 provider 分桶，不会冲突。
func (p *PoolGpt) ToAccount() *Account {
	// chat_service.credential(acc) 把 CredentialEnc 解密后直接当 Bearer
	// token 用，所以对 GPT OAuth 账号要把 CredentialEnc 设成 access_token
	// 的密文。RefreshTokenEnc 仍单独存，供 account_test_service.RefreshOAuth
	// 在 access_token 到期时刷新。
	a := &Account{
		ID:                   p.ID,
		Provider:             ProviderGPT,
		Name:                 p.Email,
		AuthType:             AuthTypeOAuth,
		CredentialEnc:        p.AccessTokenEnc,
		AccessTokenEnc:       p.AccessTokenEnc,
		RefreshTokenEnc:      p.RefreshTokenEnc,
		AccessTokenExpiresAt: p.ExpiresAt,
		LastRefreshAt:        p.LastRefreshAt,
		BaseURL:              p.BaseURL,
		ProxyID:              p.ProxyID,
		ModelWhitelist:       p.ModelWhitelist,
		Weight:               p.Weight,
		RPMLimit:             p.RPMLimit,
		TPMLimit:             p.TPMLimit,
		DailyQuota:           p.DailyQuota,
		MonthlyQuota:         p.MonthlyQuota,
		CooldownUntil:        p.CooldownUntil,
		LastUsedAt:           p.LastUsedAt,
		LastError:            p.ErrorMessage,
		LastTestAt:           p.LastTestAt,
		LastTestStatus:       p.LastTestStatus,
		LastTestLatencyMs:    p.LastTestLatencyMs,
		LastTestError:        p.LastTestError,
		ErrorCount:           p.FailureCount,
		SuccessCount:         p.SuccessCount,
		Remark:               p.Remark,
		CreatedAt:            p.CreatedAt,
		UpdatedAt:            p.UpdatedAt,
	}
	switch p.Status {
	case GPTStatusValid:
		a.Status = AccountStatusEnabled
	case GPTStatusInvalid:
		a.Status = AccountStatusBroken
	case GPTStatusDisabled:
		a.Status = AccountStatusDisabled
	case GPTStatusCooldown:
		a.Status = AccountStatusBroken
	default:
		a.Status = AccountStatusEnabled
	}
	if p.PlanType != nil || p.ChatGPTAccountID != nil {
		meta := map[string]any{}
		if p.PlanType != nil {
			meta["plan_type"] = *p.PlanType
		}
		if p.ChatGPTAccountID != nil {
			meta["chatgpt_account_id"] = *p.ChatGPTAccountID
		}
		if raw, err := json.Marshal(meta); err == nil {
			s := string(raw)
			a.OAuthMeta = &s
		}
	}
	return a
}

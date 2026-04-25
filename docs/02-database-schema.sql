-- 02. Estrutura de banco de dados (PostgreSQL)

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ===== Segurança e identidade =====
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('MANAGER','HR','EXECUTIVE','ADMIN')),
  provider TEXT NOT NULL CHECK (provider IN ('GOOGLE','MICROSOFT','LOCAL')),
  provider_subject TEXT,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(organization_id, email)
);

-- ===== Colaboradores =====
CREATE TABLE employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  manager_id UUID REFERENCES users(id),
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  current_role TEXT NOT NULL,
  seniority_level TEXT NOT NULL CHECK (seniority_level IN ('JUNIOR','PLENO','SENIOR','STAFF','PRINCIPAL','LEAD')),
  time_in_role_months INT NOT NULL DEFAULT 0,
  career_objective TEXT,
  next_step_goal TEXT,
  status TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','ON_LEAVE','OFFBOARDED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(organization_id, email)
);

CREATE TABLE employee_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  movement_type TEXT NOT NULL CHECK (movement_type IN ('PROMOTION','LATERAL_MOVE','TEAM_CHANGE','ROLE_CHANGE')),
  from_role TEXT,
  to_role TEXT,
  effective_date DATE NOT NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ===== PDI =====
CREATE TABLE pdi_templates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name TEXT NOT NULL,
  target_role TEXT NOT NULL,
  target_seniority TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE pdis (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  manager_id UUID NOT NULL REFERENCES users(id),
  template_id UUID REFERENCES pdi_templates(id),
  start_date DATE NOT NULL,
  target_review_date DATE NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('DRAFT','ACTIVE','AT_RISK','DONE','CANCELLED')),
  progress_percent NUMERIC(5,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE pdi_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pdi_id UUID NOT NULL REFERENCES pdis(id) ON DELETE CASCADE,
  horizon TEXT NOT NULL CHECK (horizon IN ('SHORT','MEDIUM','LONG')),
  title TEXT NOT NULL,
  description TEXT,
  smart_specific TEXT,
  smart_measurable TEXT,
  smart_achievable TEXT,
  smart_relevant TEXT,
  smart_timebound TEXT,
  due_date DATE,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','IN_PROGRESS','DONE','BLOCKED')),
  progress_percent NUMERIC(5,2) NOT NULL DEFAULT 0
);

CREATE TABLE pdi_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id UUID NOT NULL REFERENCES pdi_goals(id) ON DELETE CASCADE,
  responsible_type TEXT NOT NULL CHECK (responsible_type IN ('EMPLOYEE','MANAGER','BOTH')),
  action_description TEXT NOT NULL,
  due_date DATE,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','IN_PROGRESS','DONE','CANCELLED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE pdi_revisions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pdi_id UUID NOT NULL REFERENCES pdis(id) ON DELETE CASCADE,
  reviewed_by UUID NOT NULL REFERENCES users(id),
  review_date DATE NOT NULL,
  notes TEXT,
  change_summary JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ===== Feedback =====
CREATE TABLE feedback_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  author_user_id UUID NOT NULL REFERENCES users(id),
  feedback_type TEXT NOT NULL CHECK (feedback_type IN ('POSITIVE','CONSTRUCTIVE','MIXED')),
  channel TEXT NOT NULL CHECK (channel IN ('FORMAL','INFORMAL','CYCLE')),
  context TEXT,
  situation TEXT,
  behavior TEXT,
  impact TEXT,
  suggestions TEXT,
  happened_at DATE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ===== Competências =====
CREATE TABLE competencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  name TEXT NOT NULL,
  category TEXT NOT NULL CHECK (category IN ('TECHNICAL','BEHAVIORAL','LEADERSHIP')),
  description TEXT
);

CREATE TABLE role_competency_expectations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  role_name TEXT NOT NULL,
  seniority_level TEXT NOT NULL,
  competency_id UUID NOT NULL REFERENCES competencies(id),
  expected_level INT NOT NULL CHECK (expected_level BETWEEN 1 AND 5),
  UNIQUE(organization_id, role_name, seniority_level, competency_id)
);

CREATE TABLE employee_competency_assessments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  competency_id UUID NOT NULL REFERENCES competencies(id),
  assessor_user_id UUID NOT NULL REFERENCES users(id),
  current_level INT NOT NULL CHECK (current_level BETWEEN 1 AND 5),
  confidence_level INT CHECK (confidence_level BETWEEN 1 AND 5),
  evidence TEXT,
  assessed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ===== 1:1 e conversas de carreira =====
CREATE TABLE one_on_ones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  manager_id UUID NOT NULL REFERENCES users(id),
  meeting_date TIMESTAMPTZ NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('SCHEDULED','DONE','CANCELLED')),
  agenda TEXT,
  notes TEXT,
  next_steps TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE one_on_one_commitments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  one_on_one_id UUID NOT NULL REFERENCES one_on_ones(id) ON DELETE CASCADE,
  owner_type TEXT NOT NULL CHECK (owner_type IN ('EMPLOYEE','MANAGER')),
  description TEXT NOT NULL,
  due_date DATE,
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN','DONE','BLOCKED'))
);

-- ===== Promoção e sucessão =====
CREATE TABLE promotion_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES employees(id),
  proposed_role TEXT NOT NULL,
  proposed_seniority TEXT NOT NULL,
  readiness_score NUMERIC(5,2),
  status TEXT NOT NULL CHECK (status IN ('DRAFT','UNDER_REVIEW','APPROVED','REJECTED','ON_HOLD')),
  criteria_assessment JSONB,
  evidence_summary TEXT,
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE succession_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  critical_role TEXT NOT NULL,
  candidate_employee_id UUID REFERENCES employees(id),
  readiness TEXT CHECK (readiness IN ('READY_NOW','READY_6_12M','READY_12M_PLUS')),
  risk_if_vacant TEXT,
  notes TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ===== IA e auditoria =====
CREATE TABLE ai_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID REFERENCES employees(id),
  suggestion_type TEXT NOT NULL CHECK (suggestion_type IN ('PDI_ACTION','FEEDBACK_DRAFT','ONE_ON_ONE_QUESTIONS','EXEC_SUMMARY','RETENTION_RECOMMENDATION')),
  payload JSONB NOT NULL,
  model_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  accepted BOOLEAN
);

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  actor_user_id UUID REFERENCES users(id),
  entity_name TEXT NOT NULL,
  entity_id UUID,
  action TEXT NOT NULL,
  previous_data JSONB,
  new_data JSONB,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices principais
CREATE INDEX idx_employees_manager ON employees(manager_id);
CREATE INDEX idx_pdis_employee ON pdis(employee_id);
CREATE INDEX idx_feedback_employee ON feedback_entries(employee_id);
CREATE INDEX idx_1on1_employee_date ON one_on_ones(employee_id, meeting_date DESC);
CREATE INDEX idx_audit_org_time ON audit_logs(organization_id, occurred_at DESC);

# AI AGENT GOVERNANCE & ARCHITECTURE MODEL v2.0

이 문서는 자율 에이전트의 운영 아키텍처, 워크플로우 프로토콜, 리소스 계약을 정의합니다.

---

## 1. System Architecture (시스템 아키텍처)

### 1.1 Deployment Modes (배포 모드)

| Mode | 설명 | 사용 사례 |
|------|------|----------|
| **Single Agent** | 단일 LLM이 모든 역할 수행 | 소규모 작업, 빠른 프로토타이핑 |
| **Multi-Agent (CrewAI)** | 역할 기반 협업 에이전트 | 팀 시뮬레이션, 전문 분야 분리 |
| **Multi-Agent (LangGraph)** | 상태 기반 그래프 오케스트레이션 | 복잡한 워크플로우, 세밀한 제어 |

### 1.2 Core Roles (핵심 역할)

| Role | 책임 | Single | CrewAI | LangGraph |
|------|------|--------|--------|-----------|
| **Orchestrator** | 작업 분해, 위임, 통합 | 사용자 | Manager Agent | Graph Controller |
| **Planner** | 계획 수립, 단계 정의 | LLM | Planner Agent | plan_node |
| **Worker** | 단위 작업 실행 | LLM | Specialist Agents | execute_node |
| **Reviewer** | 품질 검증, 승인/반려 | 사용자+자동화 | Critic Agent | validate_node |

### 1.3 Memory Model (메모리 모델)

```
┌─────────────────────────────────────────────────────┐
│                    Memory Layers                     │
├─────────────────────────────────────────────────────┤
│ Short-term (Context)                                │
│   • 현재 작업 실행 로그                              │
│   • 도구 호출 결과                                   │
│   • 활성 대화 컨텍스트                               │
├─────────────────────────────────────────────────────┤
│ Working Memory (Session)                            │
│   • 현재 세션의 상태 (state dict)                    │
│   • 중간 산출물                                      │
│   • 에이전트 간 메시지 큐                            │
├─────────────────────────────────────────────────────┤
│ Long-term (Persistent)                              │
│   • docs/ 폴더 문서                                  │
│   • CLAUDE.md / AGENTS.md 규칙                       │
│   • memory/*.md 경험 로그                            │
│   • 성공/실패 사례 DB                                │
└─────────────────────────────────────────────────────┘
```

---

## 2. APEI Protocol (운영 프로토콜)

모든 에이전트는 **APEI 프레임워크**를 엄격히 준수합니다.

### Phase 1: ANALYZE (분석)

```yaml
actions:
  - context_load:
      files: [CLAUDE.md, 관련 docs/, 이전 memory/]
      purpose: 작업 범위 파악
  
  - ambiguity_check:
      threshold: "70% 확신 미만 시 질문"
      tool: AskUser
      rule: "가정 기반 코드 작성 금지"
  
  - scope_definition:
      output: 
        - 목표 명확화
        - 제약 조건 식별
        - 의존성 파악
```

### Phase 2: PLAN (계획)

```yaml
actions:
  - task_decomposition:
      min_steps: 3
      max_steps: 10
      format: "계층적 태스크 트리"
  
  - impact_analysis:
      check:
        - 다른 모듈 영향
        - 기존 테스트 영향
        - 성능 영향
  
  - approval_gate:
      required: true
      approver: [user, orchestrator]
      artifact: "plan.md or 구조화된 계획"
```

### Phase 3: EXECUTE (실행)

```yaml
actions:
  - atomic_changes:
      rule: "한 번에 하나의 논리적 단위만"
      max_files_per_commit: 5
  
  - tool_protocol:
      standard: MCP (Model Context Protocol)
      logging: required
  
  - state_update:
      frequency: "매 단계 완료 시"
      format:
        step: 1
        status: "completed|in_progress|blocked"
        output: "산출물 경로 또는 요약"
```

### Phase 4: ITERATE (반복 및 검증)

```yaml
actions:
  - self_correction:
      trigger: "오류 발생 시"
      process:
        1. 오류 로그 분석 (Reflect)
        2. 원인 가설 수립
        3. 수정 시도
      max_retries: 3
  
  - validation:
      automated:
        - test_suite: "npm test / pytest"
        - linter: "eslint / ruff"
        - type_check: "tsc / mypy"
      manual:
        - code_review (Reviewer)
```

---

## 3. Resource Governance (자원 관리)

### 3.1 Resource Constraints (R)

| Constraint | Value | Escalation |
|------------|-------|------------|
| Max Iterations per Task | **5턴** | → Orchestrator에 보고 |
| Max Retries on Error | **3회** | → 사용자 개입 요청 |
| Max Files per Change | **5개** | → 작업 분할 |
| Token Budget per Response | **2000 tokens** | → 요약 후 계속 |
| Max Execution Time | **10분** | → 체크포인트 저장 후 중단 |

### 3.2 Success Criteria (Φ)

```python
def is_success(task_result):
    return all([
        task_result.tests_passed == True,
        task_result.lint_errors == 0,
        task_result.type_errors == 0,
        task_result.requirements_met == True,
        task_result.reviewer_approved == True  # Optional for auto-tasks
    ])
```

### 3.3 Termination Conditions (Ψ)

| Condition | Action |
|-----------|--------|
| Φ (Success) 충족 | ✅ 정상 종료, 결과 보고 |
| R (Resource) 초과 | ⚠️ 즉시 중단, 상태 저장, Escalate |
| 사용자 개입 요청 | ⏸️ 일시 중단, 대기 |
| 복구 불가 오류 | ❌ 중단, 오류 보고, 롤백 제안 |

---

## 4. Mode-Specific Implementations

### 4.1 Single Agent Mode

```
┌─────────────────────────────────────────┐
│              Single Agent               │
│                                         │
│  User ──→ [APEI Loop] ──→ Result       │
│              │                          │
│         ┌────┴────┐                     │
│         ▼         ▼                     │
│     Analyze    Execute                  │
│         │         │                     │
│         ▼         ▼                     │
│      Plan     Iterate                   │
│                                         │
│  Tools: FileSystem, Terminal, Search    │
└─────────────────────────────────────────┘
```

**적용 방법 (Claude Code / Gemini):**

```markdown
# CLAUDE.md 또는 시스템 프롬프트에 추가

## APEI Protocol
모든 작업 시 다음 프로세스를 따르세요:

1. **ANALYZE**: 먼저 관련 파일을 읽고 요구사항을 파악하세요.
   - 모호한 점이 있으면 즉시 질문하세요.
   - 가정하지 마세요.

2. **PLAN**: 실행 전 계획을 세우세요.
   - 최소 3단계로 분해
   - 영향 범위 분석
   - 계획을 사용자에게 공유 후 승인 받기

3. **EXECUTE**: 한 번에 하나씩 실행하세요.
   - 원자적 변경 (작은 단위)
   - 매 단계 진행 상황 보고

4. **ITERATE**: 검증하고 수정하세요.
   - 테스트 실행
   - 오류 시 최대 3회 재시도
   - 5턴 초과 시 중단하고 보고

## Resource Limits
- 단일 작업당 최대 5턴
- 오류 수정 최대 3회
- 초과 시 반드시 사용자에게 상황 보고
```

---

### 4.2 Multi-Agent Mode: CrewAI

```
┌──────────────────────────────────────────────────────┐
│                    CrewAI Setup                       │
│                                                       │
│  User ──→ [Manager Agent]                            │
│                  │                                    │
│      ┌──────────┼──────────┐                         │
│      ▼          ▼          ▼                         │
│  [Planner]  [Coder]   [Reviewer]                     │
│      │          │          │                         │
│      └──────────┴──────────┘                         │
│                  │                                    │
│                  ▼                                    │
│             [Result]                                  │
└──────────────────────────────────────────────────────┘
```

**구현 예시:**

```python
from crewai import Agent, Task, Crew, Process

# === Agents ===
manager = Agent(
    role="Project Manager",
    goal="작업을 분해하고 적절한 전문가에게 위임",
    backstory="10년 경력의 기술 PM. APEI 프로토콜 전문가.",
    llm=claude_sonnet,
    verbose=True
)

planner = Agent(
    role="Technical Planner",
    goal="구현 계획 수립 및 영향 분석",
    backstory="시스템 아키텍트. 항상 계획을 먼저 세움.",
    llm=gpt4,
    allow_delegation=False
)

coder = Agent(
    role="Senior Developer",
    goal="고품질 코드 작성",
    backstory="클린 코드 원칙을 따르는 개발자.",
    llm=claude_sonnet,
    tools=[file_tool, terminal_tool],
    allow_delegation=False
)

reviewer = Agent(
    role="Code Reviewer",
    goal="코드 품질 검증 및 피드백",
    backstory="꼼꼼한 시니어 리뷰어. 버그를 잘 찾음.",
    llm=gpt4,
    allow_delegation=False
)

# === Tasks with APEI ===
analyze_task = Task(
    description="""
    [ANALYZE Phase]
    1. 요구사항 파일 읽기: {requirements}
    2. 기존 코드베이스 분석
    3. 모호한 점 목록화
    
    Output: 분석 보고서 (scope, constraints, questions)
    """,
    agent=planner,
    expected_output="분석 보고서 markdown"
)

plan_task = Task(
    description="""
    [PLAN Phase]
    분석 결과를 바탕으로:
    1. 작업을 3-10개 하위 태스크로 분해
    2. 각 태스크의 영향 범위 분석
    3. 실행 순서 결정
    
    Output: 실행 계획서
    """,
    agent=planner,
    expected_output="실행 계획서 markdown",
    context=[analyze_task]
)

execute_task = Task(
    description="""
    [EXECUTE Phase]
    계획에 따라 코드 작성:
    - 한 번에 하나의 파일만 수정
    - 매 변경 후 상태 로깅
    - 최대 5턴 내 완료
    
    Resource Limit: 5턴 초과 시 중단하고 현재 상태 보고
    """,
    agent=coder,
    expected_output="구현된 코드 파일들",
    context=[plan_task]
)

review_task = Task(
    description="""
    [ITERATE Phase - Review]
    코드 검토:
    1. 테스트 실행
    2. 린트 체크
    3. 요구사항 충족 여부
    
    Output: APPROVE 또는 REJECT + 구체적 피드백
    """,
    agent=reviewer,
    expected_output="리뷰 결과 (approve/reject + feedback)",
    context=[execute_task]
)

# === Crew ===
crew = Crew(
    agents=[manager, planner, coder, reviewer],
    tasks=[analyze_task, plan_task, execute_task, review_task],
    process=Process.sequential,  # or Process.hierarchical
    manager_agent=manager,  # for hierarchical
    verbose=True,
    memory=True,  # Enable memory
    max_rpm=10,   # Rate limiting
)

# === Run ===
result = crew.kickoff(inputs={
    "requirements": "사용자 인증 시스템 구현"
})
```

**CrewAI Resource Governance:**

```python
# Custom callback for resource limits
class APEICallback:
    def __init__(self, max_iterations=5):
        self.iteration_count = {}
        self.max_iterations = max_iterations
    
    def on_task_start(self, task, agent):
        key = f"{agent.role}:{task.description[:50]}"
        self.iteration_count[key] = 0
    
    def on_iteration(self, task, agent):
        key = f"{agent.role}:{task.description[:50]}"
        self.iteration_count[key] += 1
        
        if self.iteration_count[key] >= self.max_iterations:
            raise ResourceLimitExceeded(
                f"Max iterations ({self.max_iterations}) reached for {agent.role}"
            )
```

---

### 4.3 Multi-Agent Mode: LangGraph

```
┌────────────────────────────────────────────────────────────┐
│                     LangGraph Workflow                      │
│                                                             │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐ │
│  │ ANALYZE │───→│  PLAN   │───→│ EXECUTE │───→│ ITERATE │ │
│  └─────────┘    └─────────┘    └─────────┘    └─────────┘ │
│       │              │              │              │        │
│       │              │              │              ▼        │
│       │              │              │         ┌────────┐   │
│       │              │              │         │SUCCESS?│   │
│       │              │              │         └────────┘   │
│       │              │              │          │      │    │
│       │              │              │         YES    NO    │
│       │              │              │          │      │    │
│       │              │              │          ▼      │    │
│       │              │              │       [END]     │    │
│       │              │              │                 │    │
│       │              │              ◄─────────────────┘    │
│       │              │              (retry < 3)            │
│       │              │                                      │
│       ◄──────────────┴──────── (escalate if retry >= 3)   │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

**구현 예시:**

```python
from langgraph.graph import StateGraph, END
from typing import TypedDict, Annotated, List
import operator

# === State Definition ===
class AgentState(TypedDict):
    # Input
    task: str
    context: List[str]
    
    # APEI State
    phase: str  # analyze, plan, execute, iterate
    iteration_count: int
    retry_count: int
    
    # Working Memory
    analysis: str
    plan: List[str]
    execution_log: Annotated[List[str], operator.add]
    current_step: int
    
    # Output
    result: str
    status: str  # in_progress, success, failed, escalated
    errors: List[str]

# === Resource Limits ===
MAX_ITERATIONS = 5
MAX_RETRIES = 3

# === Node Functions ===
def analyze_node(state: AgentState) -> AgentState:
    """Phase 1: ANALYZE"""
    # Load context
    context = load_relevant_files(state["task"])
    
    # Check for ambiguity
    analysis = llm.invoke(f"""
    Analyze this task: {state["task"]}
    Context: {context}
    
    Output:
    1. Clear requirements
    2. Constraints identified  
    3. Any ambiguities (list as questions)
    """)
    
    return {
        **state,
        "phase": "analyze",
        "analysis": analysis,
        "context": context
    }

def plan_node(state: AgentState) -> AgentState:
    """Phase 2: PLAN"""
    plan = llm.invoke(f"""
    Based on analysis: {state["analysis"]}
    
    Create execution plan:
    - Break into 3-10 steps
    - Each step should be atomic
    - Include validation criteria
    
    Format: numbered list
    """)
    
    steps = parse_plan(plan)
    
    return {
        **state,
        "phase": "plan",
        "plan": steps,
        "current_step": 0
    }

def execute_node(state: AgentState) -> AgentState:
    """Phase 3: EXECUTE"""
    current = state["current_step"]
    step = state["plan"][current]
    
    # Execute single step
    result = llm.invoke(f"""
    Execute this step: {step}
    
    Previous execution log:
    {state["execution_log"]}
    
    Rules:
    - Make atomic changes only
    - Log your actions
    """)
    
    return {
        **state,
        "phase": "execute",
        "execution_log": [f"Step {current}: {result}"],
        "current_step": current + 1,
        "iteration_count": state["iteration_count"] + 1
    }

def iterate_node(state: AgentState) -> AgentState:
    """Phase 4: ITERATE"""
    # Run validation
    test_result = run_tests()
    lint_result = run_linter()
    
    if test_result.passed and lint_result.passed:
        return {
            **state,
            "phase": "iterate",
            "status": "success",
            "result": "All validations passed"
        }
    else:
        return {
            **state,
            "phase": "iterate", 
            "status": "needs_retry",
            "retry_count": state["retry_count"] + 1,
            "errors": [test_result.errors, lint_result.errors]
        }

# === Routing Functions ===
def should_continue_execution(state: AgentState) -> str:
    """Check if we should continue executing steps"""
    # Resource limit check
    if state["iteration_count"] >= MAX_ITERATIONS:
        return "escalate"
    
    # More steps to execute?
    if state["current_step"] < len(state["plan"]):
        return "execute"
    
    return "iterate"

def should_retry(state: AgentState) -> str:
    """Check iteration result"""
    if state["status"] == "success":
        return "end"
    
    if state["retry_count"] >= MAX_RETRIES:
        return "escalate"
    
    return "execute"

def escalate_node(state: AgentState) -> AgentState:
    """Handle escalation"""
    return {
        **state,
        "status": "escalated",
        "result": f"""
        ⚠️ ESCALATION REQUIRED
        
        Reason: {"Max iterations reached" if state["iteration_count"] >= MAX_ITERATIONS else "Max retries reached"}
        Current State:
        - Phase: {state["phase"]}
        - Completed Steps: {state["current_step"]}/{len(state["plan"])}
        - Errors: {state["errors"]}
        
        Execution Log:
        {chr(10).join(state["execution_log"])}
        """
    }

# === Build Graph ===
workflow = StateGraph(AgentState)

# Add nodes
workflow.add_node("analyze", analyze_node)
workflow.add_node("plan", plan_node)
workflow.add_node("execute", execute_node)
workflow.add_node("iterate", iterate_node)
workflow.add_node("escalate", escalate_node)

# Add edges
workflow.set_entry_point("analyze")
workflow.add_edge("analyze", "plan")
workflow.add_edge("plan", "execute")

# Conditional edges
workflow.add_conditional_edges(
    "execute",
    should_continue_execution,
    {
        "execute": "execute",
        "iterate": "iterate",
        "escalate": "escalate"
    }
)

workflow.add_conditional_edges(
    "iterate",
    should_retry,
    {
        "execute": "execute",
        "escalate": "escalate",
        "end": END
    }
)

workflow.add_edge("escalate", END)

# Compile
app = workflow.compile()

# === Run ===
initial_state = {
    "task": "사용자 인증 시스템 구현",
    "context": [],
    "phase": "start",
    "iteration_count": 0,
    "retry_count": 0,
    "analysis": "",
    "plan": [],
    "execution_log": [],
    "current_step": 0,
    "result": "",
    "status": "in_progress",
    "errors": []
}

result = app.invoke(initial_state)
```

**LangGraph with Checkpointing:**

```python
from langgraph.checkpoint.sqlite import SqliteSaver

# Enable persistence for long-running workflows
memory = SqliteSaver.from_conn_string(":memory:")
app = workflow.compile(checkpointer=memory)

# Run with thread_id for resume capability
config = {"configurable": {"thread_id": "project-auth-001"}}
result = app.invoke(initial_state, config)

# Resume from checkpoint if interrupted
result = app.invoke(None, config)  # Continues from last state
```

---

## 5. Communication Protocols

### 5.1 A2A (Agent-to-Agent) Message Format

```json
{
  "from": "planner",
  "to": "coder",
  "type": "task_delegation",
  "payload": {
    "task_id": "TASK-001",
    "description": "Implement login endpoint",
    "constraints": {
      "max_iterations": 5,
      "required_tests": true
    },
    "context": ["auth-spec.md", "api-design.md"],
    "expected_output": {
      "files": ["src/auth/login.py", "tests/test_login.py"],
      "validation": "pytest tests/test_login.py passes"
    }
  },
  "metadata": {
    "priority": "high",
    "deadline": "2024-01-28T22:00:00Z"
  }
}
```

### 5.2 Status Report Format

```json
{
  "agent": "coder",
  "task_id": "TASK-001",
  "status": "completed",  // in_progress, completed, blocked, failed
  "iteration": 3,
  "output": {
    "artifacts": [
      "src/auth/login.py",
      "tests/test_login.py"
    ],
    "summary": "Implemented JWT-based login with refresh tokens"
  },
  "metrics": {
    "tests_passed": 5,
    "tests_failed": 0,
    "lint_errors": 0
  },
  "next_action": "ready_for_review"
}
```

### 5.3 Escalation Format

```json
{
  "type": "escalation",
  "from": "coder",
  "reason": "resource_limit_exceeded",
  "details": {
    "limit": "max_iterations",
    "value": 5,
    "current_state": {
      "completed_steps": 3,
      "pending_steps": 2,
      "blockers": ["Unclear API response format"]
    }
  },
  "recommendation": "Clarify API spec before continuing",
  "checkpoint": "checkpoint-2024-01-28-001"
}
```

---

## 6. Quick Reference

### APEI Checklist

```markdown
□ ANALYZE
  □ Context loaded (docs, history)
  □ Ambiguities identified
  □ Questions asked (if any)

□ PLAN  
  □ Task decomposed (3-10 steps)
  □ Impact analyzed
  □ Plan approved

□ EXECUTE
  □ Atomic changes only
  □ Progress logged
  □ Within iteration limit

□ ITERATE
  □ Tests run
  □ Lint clean
  □ Review complete
```

### Resource Limits Summary

```
┌────────────────────────┬───────┬─────────────────────┐
│ Constraint             │ Limit │ On Exceed           │
├────────────────────────┼───────┼─────────────────────┤
│ Iterations per task    │ 5     │ Escalate            │
│ Retry on error         │ 3     │ Escalate            │
│ Files per change       │ 5     │ Split task          │
│ Execution time         │ 10min │ Checkpoint & pause  │
└────────────────────────┴───────┴─────────────────────┘
```

---

## 7. Hybrid Mode: CrewAI + LangGraph

CrewAI와 LangGraph의 장점을 결합한 하이브리드 아키텍처입니다.

### 7.1 Why Hybrid?

| Aspect | CrewAI | LangGraph | Hybrid |
|--------|--------|-----------|--------|
| 역할 기반 협업 | ✅ 강점 | ❌ 수동 | ✅ CrewAI 활용 |
| 상태 관리 | ❌ 제한적 | ✅ 강점 | ✅ LangGraph 활용 |
| 체크포인트/복구 | ❌ 없음 | ✅ 내장 | ✅ LangGraph 활용 |
| 토론/브레인스토밍 | ✅ 자연스러움 | ❌ 어색함 | ✅ CrewAI 활용 |
| 조건부 분기 | ❌ 제한적 | ✅ 강점 | ✅ LangGraph 활용 |
| 복잡한 워크플로우 | ❌ Sequential만 | ✅ 그래프 | ✅ LangGraph 활용 |

### 7.2 Architecture: 트램 Central Model

**역할 분담:**
- **트램 🚃**: Orchestrator + Researcher + Planner + Judge
- **Workers (Claude Code, Gemini 등)**: 실행 전담

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Chris (Human)                                │
│                        목표 제시 & 최종 승인                          │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        트램 🚃 (Central Hub)                         │
│              Orchestrator / Researcher / Planner / Judge            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     ANALYZE + PLAN                            │  │
│  │  • 요구사항 분석 (Research)                                   │  │
│  │  • 기술 조사 (Best practices, 유사 사례)                      │  │
│  │  • 작업 분해 (Task Decomposition)                             │  │
│  │  • Worker용 프롬프트 생성                                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                │                                     │
│                                ▼                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    DELEGATE (위임)                            │  │
│  │                                                               │  │
│  │         ┌─────────────┐         ┌─────────────┐             │  │
│  │         │ Claude Code │         │   Gemini    │             │  │
│  │         │  (Worker)   │         │  (Worker)   │             │  │
│  │         │             │         │             │             │  │
│  │         │ • 코드 작성 │         │ • 코드 작성 │             │  │
│  │         │ • 테스트    │         │ • 리서치    │             │  │
│  │         │ • 파일 수정 │         │ • 문서화    │             │  │
│  │         └─────────────┘         └─────────────┘             │  │
│  │               │                       │                      │  │
│  │               └───────────┬───────────┘                      │  │
│  │                           │                                  │  │
│  │                    결과물 제출                                │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                │                                     │
│                                ▼                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                     JUDGE (검증)                              │  │
│  │  • 결과물 품질 검토                                           │  │
│  │  • 요구사항 충족 여부                                         │  │
│  │  • APPROVE → 다음 단계 / 완료                                 │  │
│  │  • REJECT → 피드백 + 재작업 지시                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 7.3 트램 Central: 상세 워크플로우

```
Phase 1: ANALYZE + RESEARCH (트램)
─────────────────────────────────────
• Chris로부터 목표 수신
• 관련 컨텍스트 로딩 (memory/, docs/)
• 기술 조사 (web_search, 문서 분석)
• 모호한 점 질문 → Chris 확인
• Output: 분석 보고서

Phase 2: PLAN (트램)
─────────────────────────────────────
• 작업을 하위 태스크로 분해
• 각 태스크별 적합한 Worker 선정
  - Claude Code: 코드 구현, 복잡한 로직
  - Gemini: 리서치, 긴 문서 분석, 문서화
• Worker용 프롬프트 작성
• Output: 실행 계획 + Worker 프롬프트

Phase 3: EXECUTE (Workers via Chris)
─────────────────────────────────────
• Chris가 트램의 프롬프트를 Worker에 전달
• Worker가 실행 후 결과 반환
• Chris가 결과를 트램에게 공유
• (미래: API 연동 시 직접 호출 가능)

Phase 4: JUDGE (트램)
─────────────────────────────────────
• Worker 결과물 검토
• 체크리스트:
  □ 요구사항 충족?
  □ 코드 품질?
  □ 테스트 포함?
  □ 부작용 없음?
• APPROVE → 다음 태스크 or 완료 보고
• REJECT → 구체적 피드백 + 수정 프롬프트 생성
```

### 7.4 현실적 플로우 (현재)

아직 API 직접 연동 전이므로 Chris가 중간 다리 역할:

```
┌─────┐  목표   ┌──────┐  분석+계획   ┌──────┐
│Chris│ ──────→ │ 트램 │ ───────────→ │ 트램 │
└─────┘         └──────┘              └──────┘
                                          │
                          Worker 프롬프트 생성
                                          │
                                          ▼
┌─────┐ 프롬프트 전달 ┌────────────┐
│Chris│ ────────────→ │Claude Code │
└─────┘               │  /Gemini   │
   ▲                  └────────────┘
   │                        │
   │      결과물 전달       │
   └────────────────────────┘
   │
   │  결과 공유
   ▼
┌──────┐  Judge   ┌──────┐
│ 트램 │ ───────→ │ 트램 │ ─→ APPROVE / REJECT + 피드백
└──────┘          └──────┘
```

### 7.5 트램 Central 구현 (LangGraph 버전)

### 7.3 When to Use Each Component

```yaml
LangGraph_nodes:
  analyze:
    type: single_agent
    reason: "간단한 컨텍스트 로딩, CrewAI 오버헤드 불필요"
  
  plan:
    type: crewai_crew
    reason: "다양한 관점 필요, 토론/비평으로 더 나은 계획"
    agents: [Researcher, Architect, Critic]
  
  execute:
    type: single_agent
    reason: "실행은 단일 책임, 명확한 지시로 충분"
  
  validate:
    type: crewai_crew
    reason: "다각도 검증 필요, Reviewer + Tester 협업"
    agents: [Reviewer, Tester]
  
  escalate:
    type: single_agent
    reason: "상태 정리 및 보고만"

LangGraph_edges:
  - analyze → plan: "always"
  - plan → execute: "always"
  - execute → validate: "step_complete"
  - execute → execute: "more_steps"
  - validate → END: "approved"
  - validate → execute: "rejected, retry < 3"
  - validate → escalate: "retry >= 3"
  - execute → escalate: "iteration >= 5"
```

### 7.4 Implementation

```python
from langgraph.graph import StateGraph, END
from langgraph.checkpoint.sqlite import SqliteSaver
from crewai import Agent, Task, Crew, Process
from typing import TypedDict, List

# === State ===
class HybridState(TypedDict):
    task: str
    phase: str
    iteration: int
    retry: int
    
    # Phase outputs
    analysis: str
    plan: dict          # CrewAI output
    execution_log: List[str]
    validation: dict    # CrewAI output
    
    # Control
    status: str
    current_step: int

# === CrewAI Crews (Reusable) ===

def create_planning_crew():
    """PLAN phase: 연구 + 설계 + 비평"""
    researcher = Agent(
        role="Technical Researcher",
        goal="기술적 실현 가능성과 best practice 조사",
        backstory="꼼꼼한 리서처. 항상 근거를 찾음.",
        llm=claude_sonnet
    )
    
    architect = Agent(
        role="System Architect",
        goal="확장 가능하고 유지보수 쉬운 설계",
        backstory="10년 경력 아키텍트. 패턴을 잘 적용함.",
        llm=gpt4
    )
    
    critic = Agent(
        role="Devil's Advocate",
        goal="계획의 약점과 리스크 발견",
        backstory="비판적 사고 전문가. 빈틈을 잘 찾음.",
        llm=claude_sonnet
    )
    
    research_task = Task(
        description="기술 스택, 유사 사례, best practice 조사",
        agent=researcher,
        expected_output="리서치 결과 요약"
    )
    
    design_task = Task(
        description="리서치 기반으로 시스템 설계 및 구현 계획 수립",
        agent=architect,
        expected_output="설계 문서 + 단계별 구현 계획",
        context=[research_task]
    )
    
    critique_task = Task(
        description="설계의 약점, 리스크, 개선점 분석",
        agent=critic,
        expected_output="비평 보고서 + 최종 권고안",
        context=[design_task]
    )
    
    return Crew(
        agents=[researcher, architect, critic],
        tasks=[research_task, design_task, critique_task],
        process=Process.sequential,
        verbose=True
    )

def create_validation_crew():
    """VALIDATE phase: 리뷰 + 테스트"""
    reviewer = Agent(
        role="Code Reviewer",
        goal="코드 품질, 가독성, 패턴 준수 검증",
        backstory="시니어 리뷰어. 클린 코드 원칙 고수.",
        llm=claude_sonnet
    )
    
    tester = Agent(
        role="QA Engineer", 
        goal="기능 검증 및 엣지 케이스 발견",
        backstory="테스트 전문가. 버그를 잘 찾음.",
        llm=gpt4
    )
    
    review_task = Task(
        description="코드 리뷰: 스타일, 패턴, 보안 체크",
        agent=reviewer,
        expected_output="리뷰 결과 (approve/reject + 피드백)"
    )
    
    test_task = Task(
        description="테스트 실행 및 결과 분석",
        agent=tester,
        expected_output="테스트 결과 + 발견된 이슈",
        context=[review_task]
    )
    
    return Crew(
        agents=[reviewer, tester],
        tasks=[review_task, test_task],
        process=Process.sequential,
        verbose=True
    )

# === LangGraph Nodes ===

def analyze_node(state: HybridState) -> HybridState:
    """Single agent: 컨텍스트 로딩 및 분석"""
    analysis = single_llm.invoke(f"""
    Task: {state["task"]}
    
    1. 관련 파일/문서 식별
    2. 요구사항 명확화
    3. 제약 조건 파악
    4. 모호한 점 질문
    """)
    
    return {**state, "phase": "analyze", "analysis": analysis}

def plan_node(state: HybridState) -> HybridState:
    """CrewAI Crew: 연구 + 설계 + 비평 토론"""
    crew = create_planning_crew()
    
    result = crew.kickoff(inputs={
        "task": state["task"],
        "analysis": state["analysis"]
    })
    
    # Parse crew output into structured plan
    plan = {
        "research": result.tasks_output[0].raw,
        "design": result.tasks_output[1].raw,
        "critique": result.tasks_output[2].raw,
        "steps": parse_steps(result.tasks_output[1].raw)
    }
    
    return {**state, "phase": "plan", "plan": plan}

def execute_node(state: HybridState) -> HybridState:
    """Single agent: 원자적 실행"""
    step_idx = state["current_step"]
    step = state["plan"]["steps"][step_idx]
    
    result = single_llm.invoke(f"""
    Execute step {step_idx + 1}: {step}
    
    Rules:
    - One logical change only
    - Log all actions
    
    Previous log:
    {state["execution_log"]}
    """)
    
    new_log = state["execution_log"] + [f"Step {step_idx + 1}: {result}"]
    
    return {
        **state,
        "phase": "execute",
        "execution_log": new_log,
        "current_step": step_idx + 1,
        "iteration": state["iteration"] + 1
    }

def validate_node(state: HybridState) -> HybridState:
    """CrewAI Crew: 리뷰 + 테스트 협업"""
    crew = create_validation_crew()
    
    result = crew.kickoff(inputs={
        "code_changes": state["execution_log"],
        "requirements": state["task"]
    })
    
    validation = {
        "review": result.tasks_output[0].raw,
        "tests": result.tasks_output[1].raw,
        "approved": "approve" in result.tasks_output[0].raw.lower()
    }
    
    new_retry = state["retry"] + (0 if validation["approved"] else 1)
    
    return {
        **state,
        "phase": "validate",
        "validation": validation,
        "retry": new_retry,
        "status": "success" if validation["approved"] else "needs_retry"
    }

def escalate_node(state: HybridState) -> HybridState:
    """Single agent: 에스컬레이션 보고"""
    return {
        **state,
        "phase": "escalate",
        "status": "escalated"
    }

# === Routing ===
MAX_ITERATIONS = 5
MAX_RETRIES = 3

def after_execute(state: HybridState) -> str:
    if state["iteration"] >= MAX_ITERATIONS:
        return "escalate"
    if state["current_step"] < len(state["plan"]["steps"]):
        return "execute"
    return "validate"

def after_validate(state: HybridState) -> str:
    if state["validation"]["approved"]:
        return "end"
    if state["retry"] >= MAX_RETRIES:
        return "escalate"
    return "execute"  # Retry

# === Build Graph ===
workflow = StateGraph(HybridState)

# Nodes
workflow.add_node("analyze", analyze_node)
workflow.add_node("plan", plan_node)         # CrewAI
workflow.add_node("execute", execute_node)
workflow.add_node("validate", validate_node)  # CrewAI
workflow.add_node("escalate", escalate_node)

# Edges
workflow.set_entry_point("analyze")
workflow.add_edge("analyze", "plan")
workflow.add_edge("plan", "execute")

workflow.add_conditional_edges("execute", after_execute, {
    "execute": "execute",
    "validate": "validate",
    "escalate": "escalate"
})

workflow.add_conditional_edges("validate", after_validate, {
    "execute": "execute",
    "escalate": "escalate",
    "end": END
})

workflow.add_edge("escalate", END)

# Compile with checkpointing
memory = SqliteSaver.from_conn_string("checkpoints.db")
app = workflow.compile(checkpointer=memory)

# === Run ===
result = app.invoke(
    {
        "task": "사용자 인증 시스템 구현",
        "phase": "start",
        "iteration": 0,
        "retry": 0,
        "analysis": "",
        "plan": {},
        "execution_log": [],
        "validation": {},
        "status": "in_progress",
        "current_step": 0
    },
    {"configurable": {"thread_id": "auth-system-001"}}
)
```

### 7.5 Hybrid Best Practices

```yaml
When to use CrewAI nodes:
  - 여러 관점이 필요할 때 (연구, 설계, 검증)
  - 토론/비평으로 품질 향상 가능할 때
  - 역할 분리가 명확할 때
  
When to use Single Agent nodes:
  - 단순 실행/변환 작업
  - 빠른 응답 필요할 때
  - 역할 협업이 오버헤드일 때

LangGraph benefits:
  - 전체 워크플로우 시각화
  - 체크포인트로 장애 복구
  - 조건부 분기 명확
  - 상태 추적 용이

Cost optimization:
  - CrewAI 노드는 토큰 소비 높음
  - 중요한 결정 포인트에만 사용
  - 단순 작업은 Single Agent로
```

### 7.6 Comparison Summary

```
┌────────────────────────────────────────────────────────────────┐
│                    Approach Comparison                          │
├──────────────┬──────────────┬──────────────┬──────────────────┤
│              │ Single Agent │ CrewAI Only  │ Hybrid           │
├──────────────┼──────────────┼──────────────┼──────────────────┤
│ 복잡도       │ Low          │ Medium       │ High             │
│ 비용         │ $            │ $$$          │ $$               │
│ 품질         │ Medium       │ High         │ Highest          │
│ 제어력       │ Low          │ Low          │ High             │
│ 복구         │ None         │ None         │ Checkpoints      │
│ 토론/검증    │ No           │ Yes          │ Where needed     │
├──────────────┴──────────────┴──────────────┴──────────────────┤
│ Recommended: Hybrid for complex projects                       │
│              Single for quick tasks                            │
│              CrewAI-only for research-heavy work               │
└────────────────────────────────────────────────────────────────┘
```

---

## 8. Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-01-28 | Initial APEI framework |
| 2.0 | 2024-01-28 | Added Single/CrewAI/LangGraph modes |

---

*Last updated: 2024-01-28 by 트램 🚃*

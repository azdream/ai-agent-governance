# Hook System

Hook은 에이전트 워크플로우의 자동 전환과 품질 관리를 담당합니다.

## Hook Types

```
┌─────────────────────────────────────────────────────────────────┐
│                        Hook Lifecycle                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  UserPromptSubmit ──→ PreExecution ──→ Execution ──→ PostToolUse │
│         │                   │              │              │      │
│         ▼                   ▼              ▼              ▼      │
│   ┌──────────┐       ┌──────────┐   ┌──────────┐   ┌──────────┐ │
│   │ Init     │       │ Validate │   │ Monitor  │   │ Verify   │ │
│   │ Pipeline │       │ Input    │   │ Progress │   │ Output   │ │
│   └──────────┘       └──────────┘   └──────────┘   └──────────┘ │
│                                                          │       │
│                                                          ▼       │
│                                              Stop ──→ Transition │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Hook Definitions

### 1. UserPromptSubmit

사용자 입력 직후 실행되는 훅.

```yaml
UserPromptSubmit:
  name: pipeline-init
  trigger: "사용자 메시지 수신 시"
  actions:
    - 파이프라인 상태 초기화
    - 세션 컨텍스트 로딩
    - 이전 작업 상태 복원
  
  example:
    script: ultrawork-init-hook.sh
    purpose: "/ultrawork 파이프라인 상태 초기화"
```

### 2. PreExecution

실행 전 검증 및 준비 훅.

```yaml
PreExecution:
  name: input-validator
  trigger: "APEI Execute 단계 진입 전"
  actions:
    - 입력 유효성 검증
    - 리소스 가용성 확인
    - 의존성 체크
  
  validation_rules:
    - plan_exists: "PLAN.md 또는 계획 문서 존재"
    - resources_available: "필요한 API/도구 접근 가능"
    - dependencies_met: "선행 작업 완료 상태"
```

### 3. PostToolUse

도구 사용 후 결과 검증 훅.

```yaml
PostToolUse:
  name: output-validator
  trigger: "도구 호출 완료 후"
  actions:
    - 출력 형식 검증
    - 품질 기준 체크
    - 에러 탐지 및 분류
  
  checks:
    - validate_prompt: "에이전트/스킬별 검증 프롬프트"
    - format_check: "출력 형식 준수 여부"
    - error_detection: "오류 패턴 탐지"
```

### 4. WorkerVerify

Worker 결과물 검증 훅 (3단계 검증).

```yaml
WorkerVerify:
  name: worker-output-verify
  trigger: "Worker 작업 완료 후"
  
  verification_stages:
    functional:
      description: "기능 요구사항 충족 여부"
      checks:
        - 테스트 케이스 통과
        - 예상 출력 일치
        - 엣지 케이스 처리
    
    static:
      description: "코드 품질 검사"
      checks:
        - 린트 오류 없음
        - 타입 체크 통과
        - 코드 스타일 준수
    
    runtime:
      description: "런타임 검증"
      checks:
        - 빌드 성공
        - 통합 테스트 통과
        - 성능 기준 충족
```

### 5. Stop

작업 종료 및 전환 훅.

```yaml
Stop:
  name: phase-transition
  trigger: "현재 단계 완료 시"
  actions:
    - 상태 저장
    - 다음 단계 결정
    - 전환 실행
  
  transitions:
    specify_to_open:
      from: "/specify"
      to: "/open"
      condition: "PLAN.md 승인됨"
    
    open_to_execute:
      from: "/open"
      to: "/execute"
      condition: "Draft PR 생성됨"
    
    execute_to_publish:
      from: "/execute"
      to: "/publish"
      condition: "모든 TODO 완료"
```

## Hook Implementation

### Basic Hook Structure

```python
from typing import Dict, Any, Optional
from enum import Enum

class HookType(Enum):
    USER_PROMPT_SUBMIT = "UserPromptSubmit"
    PRE_EXECUTION = "PreExecution"
    POST_TOOL_USE = "PostToolUse"
    WORKER_VERIFY = "WorkerVerify"
    STOP = "Stop"

class HookResult:
    success: bool
    message: str
    data: Optional[Dict[str, Any]]
    next_action: Optional[str]

class Hook:
    def __init__(self, hook_type: HookType, name: str):
        self.hook_type = hook_type
        self.name = name
    
    async def execute(self, context: Dict[str, Any]) -> HookResult:
        """Override in subclass"""
        raise NotImplementedError
    
    def should_trigger(self, context: Dict[str, Any]) -> bool:
        """Check if hook should run"""
        return True
```

### Example: Worker Verify Hook

```python
class WorkerVerifyHook(Hook):
    def __init__(self):
        super().__init__(HookType.WORKER_VERIFY, "worker-verify")
        self.max_retries = 3
    
    async def execute(self, context: Dict[str, Any]) -> HookResult:
        worker_output = context.get("worker_output")
        task = context.get("task")
        
        # Stage 1: Functional
        functional_result = await self.verify_functional(worker_output, task)
        if not functional_result.success:
            return self._handle_failure("functional", functional_result)
        
        # Stage 2: Static
        static_result = await self.verify_static(worker_output)
        if not static_result.success:
            return self._handle_failure("static", static_result)
        
        # Stage 3: Runtime
        runtime_result = await self.verify_runtime(worker_output)
        if not runtime_result.success:
            return self._handle_failure("runtime", runtime_result)
        
        return HookResult(
            success=True,
            message="All verification stages passed",
            next_action="commit"
        )
    
    async def verify_functional(self, output, task) -> HookResult:
        """Check if output meets task requirements"""
        # Run tests defined in task.verify block
        test_commands = task.get("verify", {}).get("commands", [])
        for cmd in test_commands:
            result = await run_command(cmd)
            if result.exit_code != 0:
                return HookResult(success=False, message=f"Test failed: {cmd}")
        return HookResult(success=True, message="Functional tests passed")
    
    async def verify_static(self, output) -> HookResult:
        """Run linters and type checkers"""
        checks = [
            ("npm run lint", "Lint"),
            ("npm run typecheck", "TypeCheck")
        ]
        for cmd, name in checks:
            result = await run_command(cmd)
            if result.exit_code != 0:
                return HookResult(success=False, message=f"{name} failed")
        return HookResult(success=True, message="Static checks passed")
    
    async def verify_runtime(self, output) -> HookResult:
        """Run build and integration tests"""
        result = await run_command("npm run build")
        if result.exit_code != 0:
            return HookResult(success=False, message="Build failed")
        return HookResult(success=True, message="Runtime verification passed")
```

### Example: Stop Hook (Phase Transition)

```python
class StopHook(Hook):
    def __init__(self):
        super().__init__(HookType.STOP, "phase-transition")
        self.transitions = {
            "specify": self._transition_to_open,
            "open": self._transition_to_execute,
            "execute": self._transition_to_publish
        }
    
    async def execute(self, context: Dict[str, Any]) -> HookResult:
        current_phase = context.get("phase")
        
        if current_phase not in self.transitions:
            return HookResult(
                success=True,
                message="No transition defined",
                next_action="end"
            )
        
        transition_fn = self.transitions[current_phase]
        return await transition_fn(context)
    
    async def _transition_to_open(self, context) -> HookResult:
        # Check if PLAN.md is approved
        plan_approved = context.get("plan_approved", False)
        if not plan_approved:
            return HookResult(
                success=False,
                message="Plan not approved yet"
            )
        
        return HookResult(
            success=True,
            message="Transitioning to /open",
            next_action="/open"
        )
```

## Hook Registry

```python
class HookRegistry:
    def __init__(self):
        self._hooks: Dict[HookType, List[Hook]] = {}
    
    def register(self, hook: Hook):
        if hook.hook_type not in self._hooks:
            self._hooks[hook.hook_type] = []
        self._hooks[hook.hook_type].append(hook)
    
    async def trigger(self, hook_type: HookType, context: Dict) -> List[HookResult]:
        results = []
        for hook in self._hooks.get(hook_type, []):
            if hook.should_trigger(context):
                result = await hook.execute(context)
                results.append(result)
                
                # Stop on failure for critical hooks
                if not result.success and hook_type in [
                    HookType.PRE_EXECUTION,
                    HookType.WORKER_VERIFY
                ]:
                    break
        return results

# Usage
registry = HookRegistry()
registry.register(WorkerVerifyHook())
registry.register(StopHook())

# Trigger hooks
results = await registry.trigger(HookType.WORKER_VERIFY, {
    "worker_output": output,
    "task": current_task
})
```

## Hook Configuration

```yaml
# hooks.yaml
hooks:
  worker_verify:
    enabled: true
    max_retries: 3
    stages:
      functional:
        timeout_seconds: 60
        required: true
      static:
        timeout_seconds: 30
        required: true
      runtime:
        timeout_seconds: 120
        required: false  # Optional for quick iterations
  
  stop:
    enabled: true
    auto_transition: true
    require_approval:
      - execute_to_publish  # Require human approval
  
  post_tool_use:
    enabled: true
    validate_all_outputs: false
    validate_patterns:
      - "file_write"
      - "code_execute"
```

## Integration with APEI

```
┌─────────────────────────────────────────────────────────────────┐
│                    APEI + Hooks Integration                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ANALYZE ──────────────────────────────────────────────────────→│
│     │                                                            │
│     └─ [PreExecution Hook] → 입력 검증                          │
│                                                                  │
│  PLAN ─────────────────────────────────────────────────────────→│
│     │                                                            │
│     └─ [Stop Hook] → /specify 완료 → /open 전환                 │
│                                                                  │
│  EXECUTE ──────────────────────────────────────────────────────→│
│     │                                                            │
│     ├─ [PostToolUse Hook] → 각 도구 호출 검증                   │
│     ├─ [WorkerVerify Hook] → Worker 결과 3단계 검증             │
│     └─ [Stop Hook] → 모든 TODO 완료 → /publish 전환             │
│                                                                  │
│  ITERATE ──────────────────────────────────────────────────────→│
│     │                                                            │
│     └─ [WorkerVerify Hook] → 재시도 시 검증                     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

*Inspired by [Hoyeon](https://github.com/team-attention/hoyeon) hook system*

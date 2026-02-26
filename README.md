# Project2_Pipelined_DMA


## 1. 프로젝트 소개
4채널 메모리-투-메모리 DMA 컨트롤러를 2단계로 구현한 프로젝트 입니다.

- `STEP1`: Multi-channel DMA (FSM 기반 엔진)
- `STEP2`: Pipelined DMA (FIFO 분리형 데이터 흐름)
<img width="354.615" height="198.46" alt="image" src="https://github.com/user-attachments/assets/408374e8-e1b4-42bf-bb0e-4a8c3acdbb46" />
<img width="354.615" height="198.46" alt="image" src="https://github.com/user-attachments/assets/b0a0dcbf-2487-4058-ab5d-3c85c967bffb" />


이 README는 `Architecture` 설명을 제외하고 있습니다.
자세한 `Architecture`는 각 STEP별 README를 참고해주세요.

## 2. 프로젝트 개요

설계는 제어 경로에 APB, 데이터 이동 경로에 AXI를 사용합니다.

- APB: 채널별 레지스터 설정 (`SRC`, `DST`, `LEN`, `CMD`, `STATUS`)
- AXI: `AR/R`, `AW/W/B` 경로를 통한 전송
- 채널: `CH0` ~ `CH3`

## 3. 저장소 구조

```text
Project2_Pipelined_DMA/
|- STEP1/
|  |- DMAC/
|  |  |- RTL/                  # STEP1 RTL (TOP/ENGINE/CFG/ARBITER/FIFO)
|  |  `- SIM/                  # STEP1 테스트벤치 + 실행 스크립트 + 출력
|  `- scripts/common.sh        
`- STEP2/
   |- DMAC/
   |  |- RTL/                  # STEP2 RTL (TOP/INITIATOR/CFG/ARBITER/FIFO)
   |  |- SIM/                  # STEP2 테스트벤치 + 실행 스크립트 + 출력
   |  `- SYN/                  # STEP2 합성 스크립트 + 합성 리포트
   `- scripts/common.sh
```


## 4. 툴체인 및 환경
- OS: Linux
- EDA Toolchain: Synopsys
- VCS: Verilog/SystemVerilog 시뮬레이터 (Compile/Simulation 실행)
- Verdi: 디버깅/파형 분석
- Design Compiler: STEP2 RTL 합성


## 5. 결과

### 5.1 시뮬레이션 실행 시간

- STEP1: `2,183,990,000 ps` (`2,183,990 ns`)
- STEP2: `2,178,050,000 ps` (`2,178,050 ns`)

<img width="480" height="284" alt="sim_result_step1" src="https://github.com/user-attachments/assets/f902bf9f-2475-41b1-a0a4-ffa066338112" />

<img width="480" height="284" alt="sim_result_step2" src="https://github.com/user-attachments/assets/cd5d32a9-3026-4c6e-8788-b42bb23cc6ea" />


- 시뮬레이션 실행 결과 기준으로 STEP2의 구조가 약 `5,940 ns` 더 짧습니다.


### 5.2 합성 (STEP2)

리포트 파일:

- `STEP2/DMAC/SYN/OUTPUT/DMAC_TOP.qor.rpt`
- `STEP2/DMAC/SYN/OUTPUT/DMAC_TOP.area.rpt`
- `STEP2/DMAC/SYN/OUTPUT/DMAC_TOP.power.rpt`

합성 결과:

- 클럭 주기: `10.00 ns` (`100 MHz`)
- 타이밍: `WNS=0.00`, `TNS=0.00`, 위반 경로 수 = `0`
- Total cell area: `26122.445714`
- Total area: `33087.642195`
- Dynamic power: `558.3790 uW`
- Leakage power: `631.7359 uW`


## 6. RTL 파일 목록

STEP1:

- `STEP1/DMAC/RTL/DMAC_TOP.sv`
- `STEP1/DMAC/RTL/DMAC_ENGINE.sv`
- `STEP1/DMAC/RTL/DMAC_CFG.sv`
- `STEP1/DMAC/RTL/DMAC_ARBITER.sv`
- `STEP1/DMAC/RTL/DMAC_FIFO.sv`

STEP2:

- `STEP2/DMAC/RTL/DMAC_TOP.sv`
- `STEP2/DMAC/RTL/DMAC_INITIATOR.sv`
- `STEP2/DMAC/RTL/DMAC_CFG.sv`
- `STEP2/DMAC/RTL/DMAC_ARBITER.sv`
- `STEP2/DMAC/RTL/DMAC_FIFO.sv`

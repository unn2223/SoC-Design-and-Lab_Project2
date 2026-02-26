# STEP1 (Multi-channel DMA)

## 1. 프로젝트 소개
STEP1은 CPU가 APB로 채널별 전송 정보(SRC/DST/LEN)를 설정하면, 각 채널의 DMAC_ENGINE이 FSM 기반으로 동작하면서 AXI를 통해 메모리에서 데이터를 읽어와 다른 메모리 주소로 복사하는 Mem2Mem DMA입니다. DMAC_TOP은 N_CH=4로 CH0~CH3까지 4개 엔진을 인스턴스하며, 4채널이 단일 AXI 포트를 공유할 수 있도록 AR/AW/W 채널에 각각 DMAC_ARBITER를 두어 중재합니다.

STEP1의 데이터 전송은 store-and-forward 방식입니다. 엔진은 먼저 **Read burst(AR/R)**로 데이터를 받아 내부 DMAC_FIFO에 push하고, 슬레이브(메모리/메모리 컨트롤러)가 R 채널에서 마지막 beat를 RLAST로 표시하면(Read burst 완료) 그 다음에 **Write burst(AW/W/B)**로 전환하여 FIFO에서 데이터를 pop하며 목적지로 전송합니다. Write 완료 여부는 B 응답을 기준으로 확정되며, 엔진은 outstanding write 카운터로 “AW는 수락됐지만 B가 아직 안 온” 트랜잭션을 추적해 최종 done을 결정합니다.

## 2. 프로젝트 개요
- 제어 경로: APB (DMAC_CFG) — 채널별 SRC/DST/LEN/CMD/STATUS 설정
- 데이터 경로: AXI
  - Read: AR(주소 요청, DMA가 ARVALID) -> R(데이터 응답, 메모리가 RVALID/RLAST)
  - Write: AW/W(DMA가 AWVALID/WVALID, 마지막 beat에 WLAST) -> B(응답, 메모리가 BVALID)
  - 버스트 단위: 
  `ARSIZE/AWSIZE` = 3'b010 (4B/beat)
  `ARLEN/AWLEN` = beats-1, 최대 LEN=4'hF -> 16 beat = 64B
- AR/AW/W 각각에 arbiter를 두어 단일 AXI 포트를 4채널이 공유
- AXI 응답은 `RID/BID`로 채널 demux
- write 완료 여부는 outstanding write 카운터로 추적


## 3. Architecture
<img width="461" height="258" alt="image" src="https://github.com/user-attachments/assets/408374e8-e1b4-42bf-bb0e-4a8c3acdbb46" />

`DMAC_TOP` 구성:
- `DMAC_CFG`: APB 레지스터 블록
- `DMAC_ENGINE` 4개: CH0~CH3
- `DMAC_ARBITER` 3개: AR/AW/W 채널 각각 1개


### (1) DMAC_CFG(APB)

#### Global Register

| Address | Name | Bit fields | Description |
|---|---|---|---|
| `0x000` | `DMA_VER` | `[31:0]` | 고정값 `32'h0002_2025` |

#### Channel Register (CH0~CH3 동일 구조)

| Address (CH0/1/2/3) | Name | Bit fields | Description |
|---|---|---|---|
| `0x100/0x200/0x300/0x400` | `DMA_SRC` | `[31:0]` | Read source base address |
| `0x104/0x204/0x304/0x404` | `DMA_DST` | `[31:0]` | Write destination base address |
| `0x108/0x208/0x308/0x408` | `DMA_LEN` | `[15:0]` | 전송 바이트 수 |
| `0x10C/0x20C/0x30C/0x40C` | `DMA_CMD` | `[0]` | `1` write 시 `ch*_start_o` 발생 |
| `0x110/0x210/0x310/0x410` | `DMA_STATUS` | `[0]` | `ch*_done_i` 반영 (`1`이면 완료) |

`START` 동작:

- `DMA_CMD`는 레지스터에 저장되지 않고, 아래 조건일 때만 `start`가 올라갑니다.
- 예: CH0 start = `(paddr_i==12'h10C) & wren & (pwdata_i[0]==1'b1)`

`STATUS(done)` 동작:

- `DMA_STATUS[0]`은 각 엔진의 `done_o`가 `DMAC_CFG`의 `ch*_done_i`로 들어온 값을 읽는 형태입니다.
- 엔진 FSM 상 `S_IDLE`에서 `done=1`, 마지막 `S_WAIT`에서 outstanding write가 0이 되면 `done=1`로 복귀합니다.


### (2) DMAC_ENGINE(AXI)

#### FSM states:
<img width="612.3" height="343.3" alt="image" src="https://github.com/user-attachments/assets/5bb5e2ad-0c7e-4c72-a518-9895f2ffcd2d" />

- `S_IDLE`, `S_RREQ`, `S_RDATA`, `S_WREQ`, `S_WDATA`, `S_WAIT`



#### 상태별 동작:

1. `S_IDLE`
- `done=1`
- `DMA_CMD`에 `1` write되고 `LEN != 0`이면 `S_RREQ`로 이동

2. `S_RREQ`
- `ARREADY=1` handshake 시 `S_RDATA`로 이동

3. `S_RDATA`
- `RVALID & !RLAST` 동안 `S_RDATA` 유지(연속 read beat 수신)
- `RVALID & RLAST`에서 read burst 종료, `S_WREQ`로 이동

4. `S_WREQ`
- `AWREADY=1` handshake 시 `S_WDATA`로 이동
- 이때 `outstanding_wr_cnt`를 증가

5. `S_WDATA`
- `WREADY & !WLAST` 동안 `S_WDATA` 유지(연속 write beat 전송)
- `WREADY & WLAST & (len != 0)`이면 다음 burst를 위해 `S_RREQ`로 이동
- `WREADY & WLAST & (len == 0)`이면 `S_WAIT`로 이동

6. `S_WAIT`
- `BVALID & BREADY`마다 `outstanding_wr_cnt` 감소
- `outstanding_wr_cnt == 0`이면 `S_IDLE`로 이동 

#### 기존 ENGINE 대비 optimize 포인트(시뮬레이션 타임 단축):

- `S_RDATA`의 마지막 beat에서 `AWREADY=1`이면 `S_WREQ`를 거치지 않고 `S_WDATA`로 바로 진입하도록 최적화


#### AXI burst :
##### burst 길이/크기 
- 1 beat = 4B (`ARSIZE/AWSIZE = 3'b010`)
- AXI `LEN`은 `beat 수 - 1`
- `ARLEN/AWLEN = (cnt >= 64) ? 4'hF : cnt[5:2]-1`
- `cnt >= 64`이면 `LEN=15` => 16 beat => 64B
- `cnt < 64`이면 `LEN=(cnt/4)-1` 형태의 부분 burst

##### `RLAST` 의미:

- `rlast_i`는 엔진 출력이 아니라, AXI 슬레이브가 보내는 read burst 마지막 beat 표시 신호입니다.
- 엔진은 `RVALID & RREADY & RLAST` 시점에 read burst 완료로 판단합니다.

##### 간단 예시(`byte_len=160`):

- 160B = 64B + 64B + 32B 총 3번의 Burst
1. cnt=160 ≥64 -> LEN=15 -> **16 beat(64B)** 읽고 FIFO 채움 -> 16 beat(64B) 씀
2. cnt=96 ≥64 -> LEN=15 -> **16 beat(64B)** 읽고 FIFO 채움 -> 16 beat(64B) 씀
3. cnt=32 <64 -> LEN = (32/4)-1 = 8-1=7 -> **8 beat(32B)** 읽고 -> 8 beat(32B) 씀
   마지막엔 B 응답이 다 돌아왔는지(outstanding==0) 확인하고 done.

#### outstanding write 카운터:

- `awvalid_o & awready_i`면 `+1`
- `bvalid_i & bready_o`면 `-1` 
- AW handshake와 B handshake는 같은 cycle에 동시에 발생할 수 있음을 고려하여 설계함
- 이 카운터가 0이 되어야 최종 완료(`S_WAIT -> S_IDLE`)

### (3) DMAC_FIFO

- 기본 파라미터: `DEPTH_LG2=4`, `DATA_WIDTH=32`
- 깊이: `FIFO_DEPTH = 2^DEPTH_LG2 = 16` entries
- 포인터: `wrptr`, `rdptr` (MSB 포함 포인터 비교로 full/empty 판정)
- `full_o`: write pointer wrap 비트와 하위 인덱스 비교로 계산 (즉 wrptr가 rdptr보다 정확히 FIFO 깊이만큼 앞선 상태를 full_o로 판단)
- `empty_o`: `wrptr_n == rdptr_n`


엔진과의 backpressure 연동:

- read 수신 측 backpressure: `rready_o = rready & !fifo_full`
- write 송신 측 pop: `S_WDATA`에서 `wready_i` handshake 시 `fifo_rden=1`

### (4) DMAC_ARBITER(round-robin 방식)

인터페이스:

- 입력: `src_valid_i[N]`, `src_data_i[N]`
- 출력: `src_ready_o[N]`
- 출력: `dst_valid_o`, `dst_data_o`
- 입력: `dst_ready_i`

동작:

- `rr_ptr` 기준 round-robin으로 `grant_idx_n` 선택
- 선택된 소스가 valid일 때만 `dst_valid_o=1`, `dst_data_o=src_data_i[grant_idx_n]`
- 선택된 채널만 `src_ready_o[grant_idx_n] = dst_ready_i`, 나머지는 0
- `dst_valid_o && dst_ready_i` handshake 시 `rr_ptr <= grant_idx_n + 1`

1-bit ready 분배 효과(One-hot):

- 예를 들어 `awready_i`가 1bit여도, 아비터가 grant된 채널의 `awready_vec[grant]`에만 전달하고 나머지는 0으로 유지합니다.

## 4. STEP1 저장소 구조

```text
STEP1/
├─ README.md
├─ scripts/
│  └─ common.sh
└─ DMAC/
   ├─ RTL/
   │  ├─ DMAC_TOP.sv
   │  ├─ DMAC_CFG.sv
   │  ├─ DMAC_ENGINE.sv
   │  ├─ DMAC_ARBITER.sv
   │  ├─ DMAC_FIFO.sv
   │  └─ filelist.f
   └─ SIM/
      ├─ run.compile
      ├─ run.sim
      ├─ run.verdi
      ├─ sim_result_step1.png
      ├─ TB/
      │  ├─ DMAC_TOP_TB.sv
      │  ├─ AXI_INTF.sv
      │  ├─ AXI_SLAVE.sv
      │  ├─ AXI_TYPEDEF.svh
      │  ├─ timescale.v
      │  └─ filelist.f
      └─ OUTPUT/   (시뮬레이션 결과/빌드 산출물)
```

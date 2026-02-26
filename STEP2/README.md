# STEP2 (Pipelined DMA)

## 1. 프로젝트 소개

STEP2는 STEP1의 store-and-forward 방식(한 burst를 모두 읽고 나서 쓰기 시작)을 개선하여, **Read와 Write를 FIFO로 디커플링(decoupling)한 파이프라인 구조**로 Mem2Mem DMA를 구현한 프로젝트입니다.

CPU가 APB를 통해 채널별 전송 정보(SRC/DST/LEN)를 설정하면, 각 채널의 `DMAC_INITIATOR`가 **Read burst(AR)** 를 지속적으로 생성합니다. `DMAC_TOP`은 4개 채널의 AR 요청을 **`DMAC_ARBITER`로 중재**하여 단일 AXI 포트로 내보내며, **AR이 실제로 수락(handshake)되는 순간 해당 채널의 목적지 메타데이터(dst_addr/len)를 AW_FIFO에 적재**합니다.

데이터는 AXI R 채널로 들어오면 `Data_FIFO`에 `{RID, RLAST, RDATA}` 형태로 저장되고, `Data_FIFO`에 데이터가 존재하는 즉시 AXI W 채널로 `{WID, WLAST, WDATA}` 형태로 스트리밍됩니다.
즉 **`WID = RID`, `WLAST = RLAST`, `WDATA = RDATA`** 로 “읽은 스트림을 그대로 쓰는” 구조이며, 실제 쓰기 주소는 AXI AW 채널(AW_FIFO가 제공)이 결정합니다.



## 2. 프로젝트 개요

* 제어 경로: APB (`DMAC_CFG`)

  * 채널별 `SRC/DST/LEN/CMD/STATUS` 설정

* 데이터 경로: AXI (단일 포트)

  * Read: `AR`(DMA->메모리) -> `R`(메모리->DMA)
  * Write: `AW`(DMA->메모리) + `W`(DMA->메모리) -> `B`(메모리->DMA)

* 버스트 단위(코드 기준)

  * `ARSIZE/AWSIZE = 3'b010` (4B/beat, 32-bit)
  * `ARLEN/AWLEN = beats-1`, 최대 `LEN=4'hF` -> 16 beat = 64B
  * 기본적으로 64B 단위로 진행, 마지막은 부분 burst

* 채널 공유/중재

  * **AR 채널만 arbiter로 중재**
  * AW/W는 각각 FIFO에서 나오는 **단일 스트림**이므로 별도 arbiter 없음

* FIFO 기반 파이프라인

  * `AW_FIFO(40b, depth=16)` : `{AWID, AWADDR, AWLEN}` (쓰기 주소 메타)
  * `Data_FIFO(37b, depth=16)` : `{RID, RLAST, RDATA}` (읽은 데이터 + ID)

* Backpressure(overflow 방지)

  * `shared_fifo_full = aw_fifo_full | data_fifo_full`
  * FIFO가 가득 차면 initiator가 AR 발행을 멈춤



## 3. Architecture
<img width="461" height="258" alt="image" src="https://github.com/user-attachments/assets/b0a0dcbf-2487-4058-ab5d-3c85c967bffb" />


`DMAC_TOP` 구성(코드 기준):

* `DMAC_CFG` : APB 레지스터 블록
* `DMAC_INITIATOR` 4개 : CH0~CH3 (AR 생성 + dst 메타 생성)
* `DMAC_ARBITER` 1개 : AR 채널 round-robin 중재
* `DMAC_FIFO` 2개 :

  * `AW_FIFO` : `{awid[3:0], awaddr[31:0], awlen[3:0]}` (40-bit)
  * `Data_FIFO` : `{rid[3:0], rlast, rdata[31:0]}` (37-bit)




## 4. Module 상세

### (1) DMAC_CFG (APB)

#### Global Register

| Address | Name      | Bit fields | Description         |
| ------- | --------- | ---------- | ------------------- |
| `0x000` | `DMA_VER` | `[31:0]`   | 고정값 `32'h0002_2025` |

#### Channel Register (CH0~CH3 동일 구조)

| Address (CH0/1/2/3)       | Name         | Bit fields | Description                    |
| ------------------------- | ------------ | ---------- | ------------------------------ |
| `0x100/0x200/0x300/0x400` | `DMA_SRC`    | `[31:0]`   | Read source base address       |
| `0x104/0x204/0x304/0x404` | `DMA_DST`    | `[31:0]`   | Write destination base address |
| `0x108/0x208/0x308/0x408` | `DMA_LEN`    | `[15:0]`   | 전송 바이트 수                       |
| `0x10C/0x20C/0x30C/0x40C` | `DMA_CMD`    | `[0]`      | `1` write 시 `ch*_start_o` 발생   |
| `0x110/0x210/0x310/0x410` | `DMA_STATUS` | `[0]`      | `ch*_done_i` 반영 (`1`이면 done)   |

`START` 동작:

* `DMA_CMD`는 레지스터에 저장되지 않고, 아래 조건일 때 `start`가 1-cycle 펄스로 올라갑니다.
* 예: CH0 start = `(paddr_i==12'h10C) & wren & (pwdata_i[0]==1'b1)`

`STATUS(done)` 동작(코드 기준 의미):

* `DMA_STATUS[0]`은 `DMAC_INITIATOR.done_o`를 그대로 반영합니다.



### (2) DMAC_INITIATOR (채널별 AR 생성기)

역할:

* 채널별 `src_addr/dst_addr/cnt(byte_len)` 보관
* FIFO가 여유가 있는 동안 AR을 계속 발행(기본 64B burst)
* 동일한 burst 길이에 대해 dst 메타(`meta_awaddr/meta_awlen`) 생성

#### FSM states (코드 기준)

* `S_IDLE`, `S_RUN`, `S_WAIT`

#### 상태별 동작

1. `S_IDLE`

* `start_i==1` && `byte_len_i!=0`이면 시작
* 내부 레지스터 로드: `src_addr<=src_addr_i`, `dst_addr<=dst_addr_i`, `cnt<=byte_len_i`

2. `S_RUN`

* `fifo_full_i==0`일 때만 동작(backpressure)
* `arvalid_o=1`로 AR 요청 생성
* `arready_i` handshake 시

  * `src_addr += 64`, `dst_addr += 64`
  * `cnt>64`면 `cnt-=64`
  * `cnt<=64`면 `cnt=0`, `S_WAIT`로 이동

3. `S_WAIT`

* 1-cycle 후 `S_IDLE` 복귀

#### done 의미(코드)

* `done_o = (state==S_IDLE) || (state==S_WAIT)`

#### AXI burst 계산

* `arsize_o = 3'b010` (4B/beat)
* `arlen_o = (cnt >= 64) ? 4'hF : (cnt[5:2] - 1)`
* dst 메타:

  * `meta_awaddr_o = dst_addr`
  * `meta_awlen_o  = arlen_o`

#### B 채널

* `bready_o = 1'b1` (항상 수락)
* `bvalid_i`는 입력으로 들어오나, 현재 FSM/완료 로직에는 직접 사용하지 않습니다.



### (3) DMAC_ARBITER (AR 전용 round-robin)

* 입력: `src_valid_i[4]`, `src_data_i[4]`
* 출력: `dst_valid_o`, `dst_data_o`
* ready 분배: grant된 채널에만 `src_ready_o[grant] = dst_ready_i`

동작:

* `rr_ptr` 기준 round-robin으로 `grant_idx_n` 선택
* `dst_valid_o && dst_ready_i` handshake 시 `rr_ptr <= grant_idx_n + 1`



### (4) DMAC_FIFO (AW_FIFO / Data_FIFO)

* `DEPTH_LG2=4` -> depth=16
* full/empty는 MSB 포함 포인터 비교로 판정

#### FIFO 인스턴스 2개 (DMAC_TOP)

1. `AW_FIFO` (40-bit)

* 저장 필드: `{awid[3:0], awaddr[31:0], awlen[3:0]}`
* push: “어떤 채널의 AR이 handshake된 순간”
* pop: `awvalid_o && awready_i`

2. `Data_FIFO` (37-bit)

* 저장 필드: `{rid[3:0], rlast, rdata[31:0]}`
* push: `rvalid_i && rready_o`
* pop: `wvalid_o && wready_i`



### (5) DMAC_TOP (파이프라인 통합)

핵심 동작 요약:

* **AR 경로**: initiator 4개의 AR을 arbiter로 중재해 AXI로 출력 (`ARID=채널번호`)
* **AW_FIFO push**: `arready_vec[ch]==1` (즉 AR handshake)인 채널의 `{dst, len}`을 `{AWID, AWADDR, AWLEN}`으로 AW_FIFO에 push
* **AW 출력**: `awvalid_o = !aw_fifo_empty`, `awsize=3'b010`, `awburst=INCR`
* **R -> Data_FIFO -> W**:

  * `rready_o = !data_fifo_full`
  * Data_FIFO에 `{RID, RLAST, RDATA}` push
  * `wvalid_o = !data_fifo_empty`, `{WID, WLAST, WDATA} = fifo_data_rdata`
  * `wstrb_o = 4'b1111` 고정
* **Backpressure**:

  * `shared_fifo_full = aw_fifo_full | data_fifo_full`을 모든 initiator의 `fifo_full_i`로 연결
* **B ready**:

  * `bid_i`에 따라 해당 채널의 `bready_vec[ch]`를 선택하여 `bready_o`로 출력 (현재 initiator bready는 항상 1)



## 5. 동작 예시 (byte_len = 160B)

160B는 `64B + 64B + 32B`로 총 3번의 burst가 발생

* burst#1: `cnt=160` -> `LEN=15` -> 16 beat(64B)
* burst#2: `cnt=96`  -> `LEN=15` -> 16 beat(64B)
* burst#3: `cnt=32`  -> `LEN=(32/4)-1=7` -> 8 beat(32B)

파이프라인 관점에서:

* AR이 handshake 되는 순간마다 AW_FIFO에 `{dst_addr, len}`이 적재됨
* R 데이터는 도착 즉시 Data_FIFO에 쌓이고, Data_FIFO가 비지 않으면 W로 바로 흘러나감
* AW(주소)와 W(데이터)는 FIFO를 통해 decouple되어 “겹쳐서” 진행 가능



## 6. Design Trade-off & Assumptions

본 구현은 평가 지표가 (제공된 테스트벤치에 대한 시뮬레이션 수행 시간 × 합성 면적) 이었습니다. 구현을 수행하기 전 제공된 테스트벤치/파형을 분석한 결과, Read 응답(R 채널)이 in-order(또는 burst 단위로 interleave 없이) 반환되는 특성을 확인했습니다. 이에 따라 out-of-order 응답까지 완전 지원하는 구조(예: 채널별 Data FIFO 분리, ID 기반 재정렬 스케줄러 등)는 버퍼 및 제어 로직 증가로 면적이 크게 상승하여 (simulation time × area) 지표상 불리하다고 판단했고, 시스템의 완성도와 평가 성적 사이의 고민 끝에 본 구현에서는 shared FIFO 기반 파이프라인 구조로 설계를 단순화했습니다.
따라서 본 구조는 Read 응답이 in-order로 반환된다는 가정 하에서만 올바르게 동작하도록 설계되어 있으며, out-of-order가 발생할 수 있는 일반적인 AXI 환경에 적용하려면 per-ID 버퍼링 또는 재정렬 로직 등의 추가 설계가 필요합니다.

## 7. STEP2 저장소 구조

```text
STEP2/
├─ README.md
├─ scripts/
│  └─ common.sh
└─ DMAC/
   ├─ RTL/
   │  ├─ DMAC_TOP.sv
   │  ├─ DMAC_INITIATOR.sv
   │  ├─ DMAC_ARBITER.sv
   │  ├─ DMAC_FIFO.sv
   │  ├─ DMAC_CFG.sv
   │  └─ filelist.f
   ├─ SIM/
   │  ├─ run.compile
   │  ├─ run.sim
   │  ├─ run.verdi
   │  ├─ run.waveform
   │  ├─ sim_result_step2.png
   │  ├─ TB/
   │  │  ├─ DMAC_TOP_TB.sv
   │  │  ├─ AXI_INTF.sv
   │  │  ├─ AXI_SLAVE.sv
   │  │  ├─ AXI_TYPEDEF.svh
   │  │  ├─ timescale.v
   │  │  └─ filelist.f
   │  └─ OUTPUT/   (시뮬레이션 산출물)
   └─ SYN/
      ├─ run.synthesis
      ├─ script.tcl
      └─ OUTPUT/   (합성 산출물)
```

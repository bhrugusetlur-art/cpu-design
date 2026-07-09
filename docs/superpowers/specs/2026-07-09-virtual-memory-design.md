# Virtual Memory Design

## Purpose

Add demand translation for data-memory LOAD and STORE instructions while leaving the Harvard instruction ROM physically addressed. The design provides a small TLB, a page-table walker that shares the existing cache hierarchy, and a visible terminal page-fault condition.

## Scope

This is the FPGA/simulation v1 implementation. It supports one address space, one-level translation, and software-writable page-table entries. It does not add privilege levels, permissions, context switching, disk backing, automatic fault recovery, or instruction-fetch translation.

## Address and PTE format

All CPU data addresses remain 8 bits. Pages are 16 bytes:

| Field | Bits | Meaning |
|---|---:|---|
| VPN | `VA[7:4]` | Virtual page number, 0–15 |
| offset | `VA[3:0]` | Byte offset within a page |
| PPN | `PTE[3:0]` | Physical page number, 0–15 |
| valid | `PTE[7]` | Translation is present when set |

`PTE[6:4]` are reserved and read as zero. The one-byte PTE for VPN `n` resides at physical address `8'hF0 + n`; therefore the page table occupies `0xF0–0xFF`. A valid translation creates physical address `{PPN, offset}`.

## Components

### `tlb.v`

The TLB has four fully associative entries, each containing `valid`, `vpn[3:0]`, and `ppn[3:0]`. Lookup is combinational, so a hit adds no translation cycle. A 2-bit round-robin counter selects the entry overwritten by each fill. `flush` synchronously clears every valid bit and does not need to clear stored VPN/PPN fields.

### `mmu.v`

The MMU replaces `cpu_top`'s `req_pending` pulse logic and sits between `datapath` and `cache_hierarchy`. It is the sole owner of the request presented to L1. It captures virtual address, write data, and write enable before a walk, so the original access can be replayed exactly once.

The state machine behavior is:

1. **IDLE:** Observe a datapath request. A TLB hit captures/translates the request and moves to ACCESS. A miss captures the request and moves to WALK.
2. **WALK:** Keep the datapath stalled. Issue one physical read for `8'hF0 + captured_va[7:4]` through `cache_hierarchy`; wait for its response. If the PTE is valid, fill the TLB and move to ACCESS. Otherwise latch the faulting virtual address and move to FAULT.
3. **ACCESS:** Keep the datapath stalled until the single translated cache request completes. Pass returned data through for LOADs. Then return to IDLE, releasing the datapath for that clock edge.
4. **FAULT:** Assert `page_fault`, hold `stall`, and retain `fault_va` until reset. No write-back or PC update occurs for the faulting instruction.

The MMU never drives a data request at the same time as a page-table-walk request. Both use the existing L1 → L2 → `dmem` route, so a dirty PTE held in the cache remains visible to subsequent walks.

### TLB coherence

After a translated STORE completes, the MMU compares its physical address with `0xF0–0xFF`. A STORE in that range asserts the TLB `flush` input for one clock, invalidating all entries. This keeps PTE updates immediately visible on a following access without needlessly discarding TLB entries after ordinary stores. The flush occurs after the cache transaction completes; any subsequent walk observes the PTE through the coherent cache hierarchy, even before write-back reaches `dmem`.

## Integration and debug

`cpu_top.v` wires `datapath → mmu → cache_hierarchy → dmem` and exports `debug_page_fault` plus `debug_fault_va`. `basys3_top.v` adds a fault-oriented debug view showing the fault state and virtual address.

The normal cache data path remains physically addressed. Existing L1/L2 behavior, including write-back and miss stalls, is unchanged. “Zero added latency on a TLB hit” refers only to translation; normal cache hit/miss timing still applies.

## PTE boot image

For FPGA configuration and Icarus simulation, `dmem` initializes the PTE range to an identity map: `mem[8'hF0 + n] = 8'h80 | n`. Reset does not restore page-table mappings, so programs can modify PTEs and tests can preload their own map before execution.

This initialization mechanism is appropriate to v1's FPGA/simulation scope. An ASIC/tapeout revision must replace it with an explicit boot ROM or loader that creates the initial page table.

## Verification

1. `tlb_tb.v`: reset state, hit/miss lookup, fill, round-robin replacement, and flush.
2. `mmu_tb.v`: TLB-hit passthrough, cached page-table walk/fill, replay for LOAD and STORE, fault address latching/freeze, and flush after a PTE-page STORE.
3. CPU VM program test: write a PTE through its identity mapping, verify the TLB is flushed, access a remapped virtual address, then access an invalid page and verify the permanent fault state.
4. Existing `cpu_top_tb.v` and `cpu_programs_tb.v`: preserve their expected behavior under the identity map. Their compile commands add `design/tlb.v` and `design/mmu.v`; the testbench source need not change.

## Acceptance criteria

- A valid PTE remaps a LOAD and a STORE to `{PPN, offset}`.
- A TLB miss performs one cache-mediated PTE read, fills the TLB, and replays the original request once.
- A PTE STORE flushes the TLB only after it completes.
- An invalid PTE leaves the CPU permanently stalled with a stable fault signal and virtual address until reset.
- Existing CPU demo regressions keep their expected final architectural state.

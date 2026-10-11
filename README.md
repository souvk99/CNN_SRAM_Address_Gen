# Assignment 3: CNN Address Generation Across Staggered SRAM Banks
*Verilog-2001 Standard (IEEE 1364-2001)*

## 1. Specification & Mathematical Modeling

This module implements an **Address Generation and Read-Control Block** for the first layer of a **Convolutional Neural Network (CNN)** sliding window ($3 \times 3$ kernel) reading from a 4-bank SRAM:

- **Image Dimensions**: $256 \times 256$ pixels, each pixel 8-bit unsigned ($65,536\text{ Bytes} = 64\text{ KB}$).
- **Memory Architecture**:
  - 4 physical SRAM banks (Bank 0, Bank 1, Bank 2, Bank 3).
  - Each bank size: $256\text{ rows} \times 64\text{ Bytes} = 16,384\text{ Bytes} = 16\text{ KB}$.
  - Total memory across 4 banks: $4 \times 16\text{ KB} = 64\text{ KB}$.
  - Each bank has an independent 8-bit read/write port.
- **Column-Staggered Banking Scheme**:
  For an image pixel located at $(\text{row}, \text{col})$ with $\text{row} \in [0..255]$ and $\text{col} \in [0..255]$:
  $$\text{Bank Index} = \text{col} \pmod 4 \in \{0, 1, 2, 3\}$$
  $$\text{Local Column within Bank} = \lfloor \text{col} / 4 \rfloor \in \{0..63\}$$
  $$\text{Local Row within Bank} = \text{row} \in [0..255]$$

- **Traversal Direction**:
  - **Column-Major Vertical Sweep**: For a fixed column window $[\text{col\_start}, \text{col\_start}+1, \text{col\_start}+2]$, rows are swept sequentially from $0$ to $255$.
  - Once the row sweep finishes, $\text{col\_start}$ increments without bubbles or pipeline stalls.

- **Collision-Free Property**:
  For any 3 consecutive columns $\text{col}, \text{col}+1, \text{col}+2$:
  $$\{\text{col} \pmod 4, (\text{col}+1) \pmod 4, (\text{col}+2) \pmod 4\}$$
  always yields **three distinct bank IDs**. Hence, all 3 pixels required by a sliding window are read concurrently from 3 separate banks in a **single clock cycle with zero bank conflicts**.

- **Rotation-Aware Output Reassembly (24-bit bus)**:
  As the window slides, the bank containing the leftmost column rotates:
  - $\text{col\_start} = 0 \implies \text{Banks } \{0, 1, 2\}$
  - $\text{col\_start} = 1 \implies \text{Banks } \{1, 2, 3\}$
  - $\text{col\_start} = 2 \implies \text{Banks } \{2, 3, 0\}$
  - $\text{col\_start} = 3 \implies \text{Banks } \{3, 0, 1\}$ (Bank-rotation boundary)

  A spatial multiplexer maps the physical bank outputs back into true left-to-right window order:
  $$\text{pixel\_out}[23:16] = \text{Left Pixel } (\text{Col } c)$$
  $$\text{pixel\_out}[15:8]  = \text{Center Pixel } (\text{Col } c+1)$$
  $$\text{pixel\_out}[7:0]   = \text{Right Pixel } (\text{Col } c+2)$$

---

## 2. Port Definitions (`cnn_addr_gen.v`)

| Port | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 bit | System clock (100 MHz) |
| `reset_n` | Input | 1 bit | Active-low reset |
| `start` | Input | 1 bit | Initiates image window sweep |
| `bank_sel_0, 1, 2` | Output | $3 \times 2$ bits | Bank indices for the 3 current window columns |
| `bank_addr_0, 1, 2` | Output | $3 \times 8$ bits | Local row addresses within selected banks |
| `bank_col_0, 1, 2` | Output | $3 \times 6$ bits | Local column addresses within selected banks |
| `sram_rd_en` | Output | 4 bits | Individual read enables to the 4 physical SRAM banks |
| `sram_rd_row_0..3` | Output | $4 \times 8$ bits | Row addresses routed to the 4 physical SRAM banks |
| `sram_rd_col_0..3` | Output | $4 \times 6$ bits | Column addresses routed to the 4 physical SRAM banks |
| `bank_dout_0..3` | Input | $4 \times 8$ bits | Data bytes read from the 4 SRAM banks |
| `pixel_out` | Output | 24 bits | 3 reassembled pixels in spatial order `[23:0]` |
| `out_valid` | Output | 1 bit | High when `pixel_out` contains valid data |
| `busy` | Output | 1 bit | High while scanning image |
| `done` | Output | 1 bit | Pulsed high upon completing all image windows |

---

## 3. How to Run Simulation

```bash
# Compile design and testbench with standard Verilog
iverilog -o sim_3.vvp sram_4bank_cnn.v cnn_addr_gen.v tb_cnn_addr_gen.v

# Execute simulation
vvp sim_3.vvp
```

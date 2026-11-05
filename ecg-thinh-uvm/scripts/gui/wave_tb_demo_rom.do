# =============================================================================
# Waveform groups for tb_demo_rom (Questa 10.7c). Self-reporting: every
# command is catch-wrapped and failures print [wave] FAIL, with a final
# [wave] summary so a broken path is visible in the Transcript.
# Top instance = dut (tb_demo_rom). Grouped by: ROM/sample, window, feature,
# MLP, APB(seq), UART.
# =============================================================================
catch { wave delete -all }

proc addsig {path} {
    if {[catch { wave add $path } err] != 0} {
        puts "[wave] FAIL: add $path -> $err"
        return
    }
}
proc grp {name path} {
    if {[catch { wave group -label $name $path } err] != 0} {
        puts "[wave] FAIL: group $name $path -> $err"
    }
}

set N_OK 0; set N_FAIL 0

# --- ROM / sample pacer -------------------------------------------------------
addsig dut.u_rom.rom_addr
addsig dut.u_rom.rom_out
addsig dut.u_pacer.phase
addsig dut.u_pacer.wr_ptr
addsig dut.u_pacer.sample_valid
addsig dut.u_pacer.sample_data
addsig dut.u_pacer.end_of_data
grp "ROM/sample" [catch {wave getlist}]

# --- ADC rate gate ------------------------------------------------------------
addsig dut.u_adc_if.rate_tick
addsig dut.u_adc_if.data_pending
addsig dut.u_adc_if.sample_valid
addsig dut.u_adc_if.adc_overflow

# --- window buffer ----------------------------------------------------------
addsig dut.u_window.sample_cnt
addsig dut.u_window.write_ptr
addsig dut.u_window.window_ready

# --- feature ----------------------------------------------------------------
addsig dut.u_feature.state
addsig dut.u_feature.sample_cnt
addsig dut.u_feature.feature_valid

# --- MLP --------------------------------------------------------------------
addsig dut.u_ai.state
addsig dut.u_ai.class_code
addsig dut.u_ai.done

# --- APB sequencer (demo) ---------------------------------------------------
addsig dut.u_seq.state
addsig dut.u_seq.done_seen
addsig dut.u_pz.pkt_drop
addsig dut.u_pz.pkt_done

# --- UART -------------------------------------------------------------------
addsig uart_txd
addsig dut.u_uart_tx.state

puts "[wave] summary: $N_OK ok, $N_FAIL failed (see per-line FAIL above)"
radix -decimal -signed

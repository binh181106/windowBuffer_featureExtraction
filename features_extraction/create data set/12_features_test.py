import pandas as pd
import numpy as np
import os
import sys

# Đảm bảo in tiếng Việt không bị lỗi font trên Windows console
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

# ==========================================
# CẤU HÌNH (CONFIGURATION)
# ==========================================
file_path      = "E:/archive/100_ekg.csv"  # Đường dẫn file dữ liệu EKG
WINDOW_SAMPLES = 512                       # Kích thước mỗi cửa sổ: 512 mẫu
STEP_SAMPLES   = 256                       # Bước trượt (Hop size / Overlap 50%): 256 mẫu
TOTAL_SAMPLES  = 768                       # Tổng số mẫu cần xuất: 768 mẫu (2 cửa sổ trượt)

# ==========================================
# HÀM MÔ PHỎNG PHẦN CỨNG (AD8232 + ADC + TRỪ NỀN + IIR FILTER)
# ==========================================
def simulate_hardware_pipeline(signal_mV):
    # 1. Giả lập AD8232: Dải +-5mV dịch lên trung tâm 1.65V (dải từ 0.1V đến 3.2V)
    v_ad8232 = 1.65 + (signal_mV / 5.0) * 1.55
    v_ad8232 = np.clip(v_ad8232, 0.1, 3.2)
    
    # 2. Giả lập ADC 8-bit (Dải +-5V tương ứng mã 0 đến 255)
    adc_unsigned = np.clip(np.round(((v_ad8232 + 5.0) / 10.0) * 255.0), 0, 255).astype(np.int16)
    
    # 3. Tiền xử lý trên phần cứng: Trừ mã baseline (1.65V tương ứng code 169)
    adc_signed = adc_unsigned - 169
    
    # 4. Bộ lọc thông thấp IIR (Exponential Moving Average, shift_bits = 3 tương đương chia 8)
    data = adc_signed.astype(np.float32)
    filtered = np.zeros_like(data)
    y_prev = float(data[0])
    
    for i in range(len(data)):
        x_curr = float(data[i])
        y_curr = y_prev + (x_curr - y_prev) / (1 << 3)  # Mô phỏng phép dịch bit (>> 3)
        filtered[i] = y_curr
        y_prev = y_curr
        
    return filtered

# ==========================================
# FEATURE EXTRACTION — CỬA SỔ 512 MẪU
# ==========================================
def extract_12_features(signal_window, rr_curr, rr_prev):
    N        = len(signal_window)      # 512 mẫu
    half     = N // 2                  # 256 mẫu
    
    rms_val  = np.sqrt(np.mean(signal_window ** 2))
    peak_val = np.max(np.abs(signal_window))
    max_val  = np.max(signal_window)
    min_val  = np.min(signal_window)
    
    f_rms   = float(rms_val)
    f_var   = float(np.var(signal_window))
    f_peak  = float(peak_val)
    f_zc    = float(np.sum(np.diff(np.sign(signal_window)) != 0) / N)
    f_ptp   = float(max_val - min_val)
    f_crest = float(np.clip(peak_val / (rms_val + 1e-9), 0.0, 15.0))
    
    rms_h1 = np.sqrt(np.mean(signal_window[:half] ** 2))
    rms_h2 = np.sqrt(np.mean(signal_window[half:] ** 2))
    f_half_ratio = float(rms_h1 / (rms_h2 + 1e-9))
    
    f_max      = float(max_val)
    f_rr       = float(rr_curr)
    f_rr_prev  = float(rr_prev)
    f_rr_ratio = float(rr_curr / (rr_prev + 1e-9))
    f_rr_diff  = float(rr_curr - rr_prev)

    return [f_rms, f_var, f_peak, f_zc, f_ptp, f_crest, 
            f_half_ratio, f_max, 
            f_rr, f_rr_prev, f_rr_ratio, f_rr_diff]

# ==========================================
# HÀM IN BẢNG KẾT QUẢ CÓ ĐÁNH SỐ THỨ TỰ
# ==========================================
def print_feature_table(window_idx, start_idx, end_idx, feature_names, feats):
    print("=" * 86)
    print(f"       KẾT QUẢ TÍNH TOÁN 12 FEATURES - CỬA SỔ {window_idx} [{start_idx} .. {end_idx}] (512 MẪU)")
    print("=" * 86)
    print(f"{'STT':^4s} | {'Tên Đặc Trưng':14s} | {'Giá trị Thập phân (Float)':25s} | {'Q4.12 (Dec)':12s} | {'Q4.12 (Hex)':10s}")
    print("-" * 86)
    for i, (name, val) in enumerate(zip(feature_names, feats), 1):
        q_val = int(round(val * 4096))
        # Bù 2 cho giá trị 16-bit Hex
        q_hex = f"0x{q_val & 0xFFFF:04X}"
        print(f" {i:2d} | {name:14s} | {val:25.4f} | {q_val:12d} | {q_hex:10s}")
    print("=" * 86 + "\n")

# ==========================================
# MAIN PROCESS
# ==========================================
if __name__ == "__main__":
    signal_raw = None
    
    # 1. Kiểm tra và tải dữ liệu từ file hoặc sinh tín hiệu mẫu
    if os.path.exists(file_path):
        print(f"Đang xử lý file dữ liệu: {file_path}")
        df_ekg = pd.read_csv(file_path)
        lead_cols = [c for c in df_ekg.columns if 'MLII' in c]
        if not lead_cols: lead_cols = [c for c in df_ekg.columns if 'V5' in c]
        if not lead_cols: lead_cols = [df_ekg.columns[1]]
        lead_name = lead_cols[0]
        signal_raw = df_ekg[lead_name].values.astype(np.float32)
    else:
        print(f"[THÔNG BÁO] Không tìm thấy file: {file_path}")
        print("Đang tự động khởi tạo 768 mẫu tín hiệu ECG mô phỏng có nhịp tim thực tế...")
        t = np.linspace(0, 768 / 360.0, TOTAL_SAMPLES)
        ecg_mV = np.zeros(TOTAL_SAMPLES, dtype=np.float32)
        # Mô phỏng các đỉnh R tại các mẫu 120, 380, 640
        for p in [120, 380, 640]:
            ecg_mV[p-30:p-15] += 0.18 * np.sin(np.linspace(0, np.pi, 15))   # P wave
            ecg_mV[p-8:p]     -= 0.15 * np.sin(np.linspace(0, np.pi, 8))    # Q wave
            ecg_mV[p:p+12]    += 1.35 * np.sin(np.linspace(0, np.pi, 12))   # R peak
            ecg_mV[p+12:p+22] -= 0.35 * np.sin(np.linspace(0, np.pi, 10))   # S wave
            ecg_mV[p+40:p+75] += 0.28 * np.sin(np.linspace(0, np.pi, 35))   # T wave
        signal_raw = ecg_mV

    # 2. Chạy qua bộ mô phỏng phần cứng (AD8232 + ADC + Baseline + IIR)
    signal_processed = simulate_hardware_pipeline(signal_raw)
    
    # 3. Lấy đúng 768 mẫu đầu tiên và ép sang số nguyên 8-bit có dấu (chuẩn đầu vào phần cứng)
    samples_768 = signal_processed[:TOTAL_SAMPLES]
    samples_int8 = np.clip(np.round(samples_768), -128, 127).astype(np.int8)
    
    # 4. Xuất 768 mẫu ra file Hex (Bù 2, 8-bit) cho Verilog Testbench
    hex_output_file = "input_data.txt"
    with open(hex_output_file, 'w') as f:
        for val in samples_int8:
            hex_str = f"{(int(val) & 0xFF):02X}\n"
            f.write(hex_str)
            
    print(f"Đã xuất thành công {len(samples_int8)} mẫu (Hex 8-bit bù 2) ra file: '{hex_output_file}' cho Testbench.")

    feature_names = [
        'f_rms', 'f_var', 'f_peak', 'f_zc', 'f_ptp', 'f_crest', 
        'f_half_ratio', 'f_max', 'f_rr', 'f_rr_prev', 'f_rr_ratio', 'f_rr_diff'
    ]

    # ==========================================
    # PHÁT HIỆN ĐỈNH R VÀ TÍNH KHOẢNG RR TỪ TÍN HIỆU
    # (Đo chính xác khoảng cách giữa 2 đỉnh R liên tiếp, bỏ qua đoạn khuyết ở đầu cửa sổ)
    # ==========================================
    def detect_rr_peaks(signal_window, threshold=2, fs=360, hist_curr=0, hist_prev=0):
        rr_timer       = 0
        rr_current     = hist_curr
        rr_previous    = hist_prev
        first_peak     = False
        sample_delayed = signal_window[0]
        
        for i in range(1, len(signal_window)):
            s = signal_window[i]
            if sample_delayed > threshold and s < sample_delayed and rr_timer > 50:
                if not first_peak:
                    # Đỉnh R đầu tiên trong cửa sổ: làm mốc để bắt đầu đếm khoảng RR thật
                    first_peak = True
                    rr_timer   = 0
                else:
                    # Đỉnh R tiếp theo: đo chính xác khoảng cách giữa 2 đỉnh liên tiếp
                    rr_previous = rr_current if rr_current > 0 else rr_timer
                    rr_current  = rr_timer
                    rr_timer    = 0
            else:
                rr_timer += 1
            sample_delayed = s
            
        eff_prev  = rr_previous if rr_previous > 0 else rr_current
        f_rr      = float(rr_current / fs)
        f_rr_prev = float(eff_prev / fs)
        return f_rr, f_rr_prev, rr_current, rr_previous

    # ==========================================
    # CƠ CHẾ SLIDING WINDOW: TÍNH TOÁN 2 LẦN
    # (Tính trên dữ liệu mẫu số nguyên 8-bit đồng bộ với phần cứng)
    # ==========================================
    data_calc = samples_int8.astype(np.float32)
    
    # LẦN 1: CỬA SỔ 1 (512 mẫu đầu tiên: 0 đến 511)
    w1_start = 0
    w1_end   = WINDOW_SAMPLES
    window_1 = data_calc[w1_start:w1_end]
    rr_curr_1, rr_prev_1, c1, p1 = detect_rr_peaks(window_1, threshold=2, fs=360)
    feats_1  = extract_12_features(window_1, rr_curr_1, rr_prev_1)
    print_feature_table(1, w1_start, w1_end - 1, feature_names, feats_1)

    # LẦN 2: CỬA SỔ 2 (256 mẫu cũ [256..511] + 256 mẫu mới [512..767] -> 512 mẫu: 256 đến 767)
    w2_start = STEP_SAMPLES
    w2_end   = STEP_SAMPLES + WINDOW_SAMPLES
    window_2 = data_calc[w2_start:w2_end]
    rr_curr_2, rr_prev_2, c2, p2 = detect_rr_peaks(window_2, threshold=2, fs=360, hist_curr=c1, hist_prev=p1)
    feats_2  = extract_12_features(window_2, rr_curr_2, rr_prev_2)
    print_feature_table(2, w2_start, w2_end - 1, feature_names, feats_2)

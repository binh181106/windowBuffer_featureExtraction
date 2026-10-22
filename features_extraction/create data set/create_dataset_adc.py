import pandas as pd
import numpy as np
import glob
import os

# ==========================================
# CẤU HÌNH (CONFIGURATION) - CHUẨN 360HZ & FPGA PIPELINE
# ==========================================
FS_ORIGINAL     = 360       # Tần số mẫu gốc MIT-BIH (360 Hz)[cite: 2]
WINDOW_SAMPLES  = 512       # 2^9 mẫu (~1.422s) -> Dịch phải 9 bit (>> 9) trên phần cứng
HALF_WINDOW     = 256       # WINDOW_SAMPLES // 2 (2^8 mẫu) -> Dịch phải 8 bit (>> 8)
folder_path     = "E:/archive"  # ĐƯỜNG DẪN DỮ LIỆU CỦA BẠN[cite: 6]

# Các ký hiệu nhịp tim hợp lệ từ file EKG (đã lọc rác Q, |, v.v.)
beat_symbols = ['N', 'L', 'R', 'A', 'a', 'J', 'S', 'V', 'F', '!', 'e', 'j', 'E', '/', 'f']
arrhythmia_symbols = ['L', 'R', 'A', 'a', 'J', 'S', 'V', 'F', '!', 'e', 'j', 'E', '/', 'f']

# ==========================================
# HÀM MÔ PHỎNG PHẦN CỨNG (AD8232 + ADC + TRỪ NỀN + IIR FILTER)
# ==========================================
def simulate_hardware_pipeline(signal_mV):
    """
    Giả lập 100% luồng phần cứng thực tế:
    1. MIT-BIH (mV) -> AD8232 (0.1V - 3.2V, tâm 1.65V)
    2. Qua ADC 8-bit (Dải thu +-5V -> Mã 0 đến 255)
    3. Trừ nền 169 (Baseline subtraction đưa về số có dấu)
    4. Bộ lọc thông thấp IIR (Khử răng cưa lượng tử hóa)
    """
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
        y_curr = y_prev + (x_curr - y_prev) / (1 << 3) # Mô phỏng phép dịch bit (>> 3)
        filtered[i] = y_curr
        y_prev = y_curr
        
    return filtered

# ==========================================
# FEATURE EXTRACTION — CỬA SỔ 512 MẪU (360HZ)
# ==========================================
def extract_12_features(signal_window, rr_curr, rr_prev):
    """
    Trích xuất 12 đặc trưng trực tiếp trên cửa sổ 512 mẫu (nguyên bản từ luồng phần cứng).
    """
    N        = len(signal_window)      # 512 mẫu
    half     = N // 2                  # 256 mẫu
    
    # --- Tính toán thống kê cơ bản ---
    rms_val  = np.sqrt(np.mean(signal_window ** 2))
    peak_val = np.max(np.abs(signal_window))
    max_val  = np.max(signal_window)
    min_val  = np.min(signal_window)
    
    # 1. f_rms: Năng lượng tín hiệu
    f_rms   = float(rms_val)
    
    # 2. f_var: Phương sai (độ tản mát dữ liệu)
    f_var   = float(np.var(signal_window))
    
    # 3. f_peak: Đỉnh trị tuyệt đối lớn nhất
    f_peak  = float(peak_val)
    
    # 4. f_zc: Zero Crossing Rate (Tần số cắt đường 0)
    f_zc    = float(np.sum(np.diff(np.sign(signal_window)) != 0) / N)
    
    # 5. f_ptp: Peak-to-Peak (Biên độ đỉnh - đáy)
    f_ptp   = float(max_val - min_val)
    
    # 6. f_crest: Crest Factor (Phát hiện gai nhọn bất thường như PVC)
    f_crest = float(np.clip(peak_val / (rms_val + 1e-9), 0.0, 15.0))
    
    # 7. f_half_ratio: So sánh năng lượng nửa đầu (256 mẫu) vs nửa sau (256 mẫu)
    rms_h1 = np.sqrt(np.mean(signal_window[:half] ** 2))
    rms_h2 = np.sqrt(np.mean(signal_window[half:] ** 2))
    f_half_ratio = float(rms_h1 / (rms_h2 + 1e-9))
    
    # 8. f_max: Giá trị lớn nhất
    f_max   = float(max_val)
    
    # --- CÁC ĐẶC TRƯNG CHUỖI THỜI GIAN (RR HISTORY) ---
    # 9. f_rr: Khoảng RR hiện tại (giây)
    f_rr      = float(rr_curr)
    
    # 10. f_rr_prev: Khoảng RR ngay trước đó (giây)
    f_rr_prev = float(rr_prev)
    
    # 11. f_rr_ratio: Tỷ lệ biến thiên (Current / Prev)
    f_rr_ratio = float(rr_curr / (rr_prev + 1e-9))
    
    # 12. f_rr_diff: Độ lệch tuyệt đối (Current - Prev)
    f_rr_diff  = float(rr_curr - rr_prev)

    return [f_rms, f_var, f_peak, f_zc, f_ptp, f_crest, 
            f_half_ratio, f_max, 
            f_rr, f_rr_prev, f_rr_ratio, f_rr_diff]

# ==========================================
# LOGIC GÁN NHÃN (LABELING) - 4 CLASSES
# ==========================================
def get_label(symbol, hr, rr_curr, rr_prev):
    # 1. Ưu tiên 1: Bất kỳ ký hiệu nào khác 'N' trong nhóm beat hợp lệ -> Bất thường (3)
    if symbol in arrhythmia_symbols:
        return 3  # Abnormal (Arrhythmia)
    
    # 2. Ưu tiên 2: Nhãn là 'N' nhưng nhịp biến thiên đột ngột > 20% -> Bất thường (3)
    if rr_prev > 0:
        change_pct = abs(rr_curr - rr_prev) / rr_prev
        if change_pct > 0.20: 
            return 3  # Abnormal
            
    # 3. Ưu tiên 3: Nhãn 'N', nhịp đều nhưng tốc độ vượt ngưỡng sinh lý
    if hr > 100.0: 
        return 1  # Fast (Tachycardia)
    if hr < 60.0:  
        return 2  # Slow (Bradycardia)
    
    # 4. Còn lại: Nhãn 'N', nhịp đều và nằm trong khoảng [60, 100] BPM
    return 0  # Normal

# ==========================================
# MAIN PROCESS
# ==========================================
if __name__ == "__main__":
    print("=" * 60)
    print("BẮT ĐẦU TẠO DATASET 12 ĐẶC TRƯNG (360Hz, 512 SAMPLES, AD8232 + IIR PIPELINE)")
    print("=" * 60)
    
    dataset_rows = []
    ekg_files = glob.glob(os.path.join(folder_path, "*_ekg.csv"))
    
    count_files = 0
    
    for ekg_file in ekg_files:
        patient_id = os.path.basename(ekg_file).split('_')[0]
        
        try:
            df_ekg = pd.read_csv(ekg_file)
        except Exception as e:
            continue

        # Chọn cột tín hiệu (Ưu tiên MLII > V5 > Cột 1)
        lead_cols = [c for c in df_ekg.columns if 'MLII' in c]
        if not lead_cols: lead_cols = [c for c in df_ekg.columns if 'V5' in c]
        if not lead_cols: lead_cols = [df_ekg.columns[1]]
        
        lead_name = lead_cols[0]
        signal_raw = df_ekg[lead_name].values.astype(np.float32)
        
        # === CHẠY QUA TOÀN BỘ CHUỖI GIẢ LẬP PHẦN CỨNG (AD8232 + ADC + TRỪ NỀN + IIR FILTER) ===
        signal_processed = simulate_hardware_pipeline(signal_raw)
        
        # Lọc các dòng có nhãn đỉnh bóp (cột 'symbol' khác NaN)
        if 'symbol' not in df_ekg.columns: continue
        df_ekg['index'] = df_ekg.index
        valid_beats = df_ekg[df_ekg['symbol'].isin(beat_symbols)].reset_index(drop=True)
        if len(valid_beats) < 3: continue
        
        prev_rr_sec = None
        
        for i in range(1, len(valid_beats) - 1):
            idx = int(valid_beats.loc[i, 'index'])
            prev_idx_sample = int(valid_beats.loc[i-1, 'index'])
            sym = str(valid_beats.loc[i, 'symbol'])
            
            # Tính RR interval trên miền 360Hz
            rr_samples = idx - prev_idx_sample
            if rr_samples <= 0: continue
            
            rr_sec = rr_samples / FS_ORIGINAL
            
            # Bỏ qua nếu khoảng RR phi lý
            if rr_sec < 0.20 or rr_sec > 3.0:
                prev_rr_sec = None
                continue
                
            if prev_rr_sec is None:
                prev_rr_sec = rr_sec
                continue
                
            hr = 60.0 / rr_sec
            
            # Cắt cửa sổ 512 mẫu quanh đỉnh R (idx) từ tín hiệu ĐÃ QUA LỌC PHẦN CỨNG
            start = idx - HALF_WINDOW
            end   = idx + HALF_WINDOW
            
            if start < 0 or end > len(signal_processed):
                prev_rr_sec = rr_sec
                continue
            
            window_data = signal_processed[start:end]
            
            # Trích xuất 12 đặc trưng từ cửa sổ 512 mẫu
            feats = extract_12_features(window_data, rr_sec, prev_rr_sec)
            
            # Gán nhãn 4 lớp
            label = get_label(sym, hr, rr_sec, prev_rr_sec)
            
            dataset_rows.append([patient_id, hr, label] + feats)
            prev_rr_sec = rr_sec
            
        count_files += 1
        if count_files % 5 == 0:
            print(f"Processed {count_files} files...")

    # Lưu file CSV kết quả
    feature_cols = [
        'f_rms', 'f_var', 'f_peak', 'f_zc', 'f_ptp', 'f_crest', 
        'f_half_ratio', 'f_max', 
        'f_rr', 'f_rr_prev', 'f_rr_ratio', 'f_rr_diff'
    ]
    
    cols = ['patient_id', 'hr', 'label'] + feature_cols
    
    # Lưu file cùng thư mục với script này
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_file = os.path.join(script_dir, "AI_Training_12_Features_360Hz.csv")
    
    df_final = pd.DataFrame(dataset_rows, columns=cols)
    df_final.to_csv(out_file, index=False)
    
    print("\n" + "=" * 60)
    print("HOÀN TẤT TẠO DATASET!")
    print(f"File saved: {out_file}")
    print(f"Total samples: {len(df_final)}")
    print("Label Distribution (0: Normal, 1: Fast, 2: Slow, 3: Abnormal):")
    print(df_final['label'].value_counts().sort_index())
    print("=" * 60)
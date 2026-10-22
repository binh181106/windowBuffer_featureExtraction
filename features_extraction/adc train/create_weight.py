import torch
import torch.nn as nn
import pandas as pd
import numpy as np
import os

# ==========================================
# CẤU HÌNH XUẤT 1 FILE WEIGHT.HEX DUY NHẤT
# ==========================================
MODEL_FILE       = "e:/robot_mapping_sim/AI_360hz_rework/adc train 2/mlp_fpga_best.pth"
SCALER_FILE      = "e:/robot_mapping_sim/AI_360hz_rework/adc train 2/scaler_params_fpga.csv"
HEX_OUT_FILE     = "e:/robot_mapping_sim/AI_360hz_rework/adc train 2/weight.hex"

TOTAL_BITS       = 16     # 16-bit signed
FRAC_BITS        = 12     # Định dạng Q4.12 (nhân với 4096)
SCALE_FACTOR     = 1 << FRAC_BITS

# LƯU Ý QUAN TRỌNG VỀ SCALER TRÊN VERILOG:
# - Để True nếu mạch Verilog tính:  x_norm = (x - mean) * inv_scale (Phép nhân: 1 / scale)
# - Để False nếu mạch Verilog tính: x_norm = (x - mean) / scale     (Giữ nguyên cột 'scale' gốc)
USE_INVERSE_SCALE = True  

class HeartRateNet(nn.Module):
    def __init__(self):
        super(HeartRateNet, self).__init__()
        self.fc1 = nn.Linear(12, 8)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(8, 4) 

    def forward(self, x):
        return self.fc2(self.relu(self.fc1(x)))

def float_to_hex16(val):
    """Lượng tử hóa số thực sang Q4.12 và chuyển thành mã HEX 16-bit bù 2"""
    scaled = int(np.round(val * SCALE_FACTOR))
    clipped = int(np.clip(scaled, -(1 << (TOTAL_BITS - 1)), (1 << (TOTAL_BITS - 1)) - 1))
    if clipped < 0:
        clipped = (1 << TOTAL_BITS) + clipped
    return f"{clipped:04X}"

if __name__ == "__main__":
    # 1. Load thông số StandardScaler (ĐƯA LÊN ĐẦU FILE)
    if not os.path.exists(SCALER_FILE):
        raise FileNotFoundError(f"Không tìm thấy {SCALER_FILE}!")
    
    df_sc = pd.read_csv(SCALER_FILE)
    means = df_sc['mean'].values.flatten()          # 12 phần tử (Index 0 -> 11)
    
    if USE_INVERSE_SCALE:
        scales = (1.0 / (df_sc['scale'].values + 1e-9)).flatten() # 12 phần tử 1/std (Index 12 -> 23)
    else:
        scales = df_sc['scale'].values.flatten()    # 12 phần tử std gốc (Index 12 -> 23)

    # 2. Load model đã train
    if not os.path.exists(MODEL_FILE):
        raise FileNotFoundError(f"Không tìm thấy {MODEL_FILE}!")
        
    model = HeartRateNet()
    model.load_state_dict(torch.load(MODEL_FILE, map_location="cpu"))
    model.eval()

    w1 = model.fc1.weight.detach().numpy().flatten()  # 96 phần tử (Index 24 -> 119)
    b1 = model.fc1.bias.detach().numpy().flatten()    # 8 phần tử  (Index 120 -> 127)
    w2 = model.fc2.weight.detach().numpy().flatten()  # 32 phần tử (Index 128 -> 159)
    b2 = model.fc2.bias.detach().numpy().flatten()    # 4 phần tử  (Index 160 -> 163)

    # 3. Nối theo đúng thứ tự: SCALER (Mean -> Scale) -> W1 -> B1 -> W2 -> B2
    all_weights = np.concatenate([means, scales, w1, b1, w2, b2])

    # 4. Ghi ra 1 file weight.hex duy nhất
    script_dir = os.path.dirname(os.path.abspath(__file__))
    out_path = os.path.join(script_dir, HEX_OUT_FILE)

    with open(out_path, "w") as f:
        for val in all_weights:
            f.write(f"{float_to_hex16(val)}\n")

    print("=" * 60)
    print(f"[HOÀN TẤT] Đã xuất toàn bộ tham số ra: {out_path}")
    print(f"Tổng số dòng HEX: {len(all_weights)} (Định dạng 16-bit Q{TOTAL_BITS-FRAC_BITS}.{FRAC_BITS})")
    print("Sơ đồ địa chỉ (Memory Map):")
    print("  - [000 .. 011] : scaler_mean  (12)")
    print(f"  - [012 .. 023] : {'scaler_inv_std (1/scale)' if USE_INVERSE_SCALE else 'scaler_std (scale)'} (12)")
    print("  - [024 .. 119] : fc1.weight   (8x12 = 96)")
    print("  - [120 .. 127] : fc1.bias     (8)")
    print("  - [128 .. 159] : fc2.weight   (4x8  = 32)")
    print("  - [160 .. 163] : fc2.bias     (4)")
    print("=" * 60)
import torch
import torch.nn as nn
import torch.optim as optim
import pandas as pd
import numpy as np
import os
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
from sklearn.utils.class_weight import compute_class_weight
from sklearn.metrics import classification_report, confusion_matrix
from torch.utils.data import DataLoader, TensorDataset

# ==========================================
# CẤU HÌNH TRAINING (CHUẨN 360HZ)
# ==========================================
CSV_FILE    = "AI_Training_12_Features_360Hz_adc.csv"
MODEL_FILE  = "mlp_fpga_best.pth"
BATCH_SIZE  = 64    
MAX_EPOCHS  = 250   
LR          = 0.003 

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

# ==========================================
# 1. LOAD & CHUẨN BỊ DATA
# ==========================================
if not os.path.exists(CSV_FILE):
    raise FileNotFoundError(f"Không tìm thấy file {CSV_FILE}. Hãy chạy file create_dataset.py trước!")

df = pd.read_csv(CSV_FILE)

feature_cols = [c for c in df.columns if c.startswith('f_')]
print(f"Features detected ({len(feature_cols)}): {feature_cols}")

X = df[feature_cols].values
y = df['label'].values

# Chia tập Train/Val/Test (70% / 15% / 15%)
X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.3, stratify=y, random_state=42)
X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.5, stratify=y_temp, random_state=42)

# Chuẩn hóa Z-score
scaler = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_val   = scaler.transform(X_val)
X_test  = scaler.transform(X_test)

# Lưu thông số scaler cho FPGA
params = pd.DataFrame({'feature': feature_cols, 'mean': scaler.mean_, 'scale': scaler.scale_})
params.to_csv("scaler_params_fpga.csv", index=False)
print("Saved scaler params to 'scaler_params_fpga.csv'.")

# Chuyển sang Tensor
X_train_t = torch.FloatTensor(X_train).to(device)
y_train_t = torch.LongTensor(y_train).to(device)
X_val_t   = torch.FloatTensor(X_val).to(device)
y_val_t   = torch.LongTensor(y_val).to(device)
X_test_t  = torch.FloatTensor(X_test).to(device)
y_test_t  = torch.LongTensor(y_test).to(device)

train_loader = DataLoader(TensorDataset(X_train_t, y_train_t), batch_size=BATCH_SIZE, shuffle=True)

# ==========================================
# 2. ĐỊNH NGHĨA MODEL 12-8-4
# ==========================================
class HeartRateNet(nn.Module):
    def __init__(self):
        super(HeartRateNet, self).__init__()
        self.fc1 = nn.Linear(12, 8)
        self.relu = nn.ReLU()
        self.fc2 = nn.Linear(8, 4) 

    def forward(self, x):
        out = self.fc1(x)
        out = self.relu(out)
        out = self.fc2(out)
        return out

model = HeartRateNet().to(device)

# ==========================================
# 3. CLASS WEIGHTS TỰ ĐỘNG & OPTIMIZER
# ==========================================
# Tính trọng số cân bằng tự động dựa trên phân bố thực tế của tập Train (dùng căn bậc 2 để làm mượt)
raw_weights = compute_class_weight(class_weight='balanced', classes=np.unique(y_train), y=y_train)
smooth_weights = np.sqrt(raw_weights)
print(f"Computed Smooth Class Weights: {np.round(smooth_weights, 4)}")

class_weights_t = torch.FloatTensor(smooth_weights).to(device)
criterion = nn.CrossEntropyLoss(weight=class_weights_t)
optimizer = optim.Adam(model.parameters(), lr=LR, weight_decay=1e-4)
scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode='min', factor=0.5, patience=10)

# ==========================================
# 4. TRAINING LOOP (ĐÃ BỔ SUNG ĐẦY ĐỦ)
# ==========================================
history = {
    'train_loss': [], 'val_loss': [],
    'train_acc': [], 'val_acc': []
}

best_val_loss = float('inf')
best_acc = 0.0
patience = 25
counter = 0

print(f"\nStarting training for {MAX_EPOCHS} epochs...")

for epoch in range(MAX_EPOCHS):
    model.train()
    running_loss = 0.0
    correct_train = 0
    total_train = 0
    
    for batch_x, batch_y in train_loader:
        optimizer.zero_grad()
        outputs = model(batch_x)
        loss = criterion(outputs, batch_y)
        loss.backward()
        optimizer.step()
        
        running_loss += loss.item() * batch_x.size(0)
        _, predicted = torch.max(outputs, 1)
        total_train += batch_y.size(0)
        correct_train += (predicted == batch_y).sum().item()
        
    epoch_train_loss = running_loss / total_train
    epoch_train_acc  = 100.0 * correct_train / total_train
    
    # Đánh giá trên tập Validation
    model.eval()
    with torch.no_grad():
        val_outputs = model(X_val_t)
        val_loss = criterion(val_outputs, y_val_t).item()
        _, val_preds = torch.max(val_outputs, 1)
        val_acc = 100.0 * (val_preds == y_val_t).sum().item() / y_val_t.size(0)
        
    history['train_loss'].append(epoch_train_loss)
    history['val_loss'].append(val_loss)
    history['train_acc'].append(epoch_train_acc)
    history['val_acc'].append(val_acc)
    
    scheduler.step(val_loss)
    
    if (epoch + 1) % 10 == 0 or epoch == 0:
        print(f"Epoch [{epoch+1:3d}/{MAX_EPOCHS}] | "
              f"Train Loss: {epoch_train_loss:.4f} Acc: {epoch_train_acc:.2f}% | "
              f"Val Loss: {val_loss:.4f} Acc: {val_acc:.2f}%")
        
    # Lưu model tốt nhất và kiểm tra Early Stopping
    if val_loss < best_val_loss:
        best_val_loss = val_loss
        best_acc = val_acc
        torch.save(model.state_dict(), MODEL_FILE)
        counter = 0
    else:
        counter += 1
        if counter >= patience:
            print(f"\n[Early Stopping] Dừng sớm tại Epoch {epoch+1}. Best Val Acc: {best_acc:.2f}%")
            break

# ==========================================
# 5. ĐÁNH GIÁ & VẼ BIỂU ĐỒ
# ==========================================
print("\n" + "="*30)
print("EVALUATION & VISUALIZATION")
print("="*30)

model.load_state_dict(torch.load(MODEL_FILE))
model.eval()

with torch.no_grad():
    outputs = model(X_test_t)
    _, preds = torch.max(outputs, 1)

y_true_np = y_test
y_pred_np = preds.cpu().numpy()
class_names = ['Normal (0)', 'Fast (1)', 'Slow (2)', 'Abnormal (3)']

# --- VẼ BIỂU ĐỒ 1: LOSS & ACCURACY ---
plt.figure(figsize=(14, 5))

plt.subplot(1, 2, 1)
plt.plot(history['train_acc'], label='Train Acc')
plt.plot(history['val_acc'], label='Val Acc')
plt.title('Training and Validation Accuracy (360Hz)')
plt.xlabel('Epochs')
plt.ylabel('Accuracy (%)')
plt.legend()
plt.grid(True)

plt.subplot(1, 2, 2)
plt.plot(history['train_loss'], label='Train Loss')
plt.plot(history['val_loss'], label='Val Loss')
plt.title('Training and Validation Loss (360Hz)')
plt.xlabel('Epochs')
plt.ylabel('Loss')
plt.legend()
plt.grid(True)

plt.tight_layout()
plt.savefig("Training_Curves.png", dpi=300)
print("Saved chart: Training_Curves.png")
plt.show()

# --- VẼ BIỂU ĐỒ 2: CONFUSION MATRIX ---
cm = confusion_matrix(y_true_np, y_pred_np)
plt.figure(figsize=(8, 6))
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', 
            xticklabels=class_names, yticklabels=class_names)
plt.ylabel('Thực tế (True Label)')
plt.xlabel('Dự đoán (Predicted Label)')
plt.title('Confusion Matrix - Kết quả kiểm thử (360Hz)')
plt.savefig("Confusion_Matrix.png", dpi=300)
print("Saved chart: Confusion_Matrix.png")
plt.show()

# --- XUẤT BÁO CÁO CHI TIẾT ---
print("\nBÁO CÁO CHI TIẾT (Classification Report):")
print(classification_report(y_true_np, y_pred_np, target_names=class_names, digits=4))
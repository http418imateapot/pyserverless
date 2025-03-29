# PyServerless

## 簡介

PyServerless 是一個專為 Python 開發人員設計的無伺服器服務開發工具，包含簡化 AWS Lambda 等無伺服器服務的部署和管理流程。

## 架構

1. **AWS Lambda 模組**：
   - 提供 Lambda 函數的開發範例
   - 提供 PowerShell 和 Linux bash 腳本用於封裝和部署

## AWS Lambda 模組 Build Script 使用指南

專案中的 `build_lambda.ps1` 或 `build_lambda.sh` 腳本，用於將您的 Lambda 函數打包成可部署的 ZIP 檔案。

### 用法

```shell
.\PyServerless\aws\lambda\build_lambda.ps1 [選項]
```

```shell
./PyServerless/aws/lambda/build_lambda.sh [選項]
```

### 選項

- `-h, --help`：顯示說明文件
- `-p, --package DIR`：指定要建構的套件目錄
- 預設：自動掃描 Lambda 套件目錄並列出由使用者選擇

### 使用範例

1. **互動式選擇套件**：
   ```shell
   .\PyServerless\aws\lambda\build_lambda.ps1
   ```
   腳本將搜尋並列出所有符合條件的套件目錄，讓您選擇要建構的套件。

2. **指定套件目錄**：
   ```shell
   .\PyServerless\aws\lambda\build_lambda.ps1 -p C:\Path\To\my_function_package
   ```
   直接指定要建構的套件目錄。

### 設計特色

1. **套件偵測**
   - 自動識別符合命名慣例（以 `_package` 結尾）的目錄
   - 確認目錄中包含必要的 `lambda_function.py` 檔案

2. **多壓縮工具支援**
   - 自動偵測並使用系統中可用的壓縮工具
   - 依照優先順序嘗試使用：
     1. 7-Zip (`7z`)：提供最佳壓縮率
     2. Zip (`zip`)：常見於 Git Bash 或 Linux 環境
   - 若以上工具都不存在，腳本會提示安裝建議

3. **依賴管理**
   - 自動從 `requirements.txt` 安裝函數依賴項
   - 支援 `requirements-dev.txt` 用於開發依賴

4. **結構化輸出**
   - 建構的 Lambda 函數套件存放在統一的 `dist` 目錄中
   - 臨時構建文件保存於 `build` 目錄，便於檢查和除錯


### AWS Lambda 模組套件目錄結構要求

要使用此框架，您的 Lambda 函數套件目錄應遵循以下結構：

```
my_function_package/
├── lambda_function.py     # 必要：包含 Lambda 處理函數
├── requirements.txt       # 可選：函數依賴項列表
└── requirements-dev.txt   # 可選：開發依賴項列表
```

其中，目錄名稱必須以 `_package` 結尾，以便腳本能夠正確識別。

### 注意事項

- 確保系統中已安裝 Python 和 pip
- 建議安裝 7-Zip 以獲得最佳壓縮效能
- 如果看到權限相關錯誤，請以管理員權限執行 PowerShell

# RHEL 9 Foomatic調査環境

UBI 9.8とRHEL提供の`cups-filters` RPMを使用し、Ricoh Basic PS PPD
Ver.1.12.2に対する`foomatic-rip`の拒否動作と、ハッシュ登録による回避を
確認する環境です。CUPSおよびsystemdは起動しません。

## イメージに含まれる範囲

イメージのビルド時に、次の処理まで実施します。

1. `cups-filters`をUBIリポジトリからインストール
2. Ricoh公式サイトの利用条件に同意してPPDアーカイブを取得
3. 白黒版とカラー版のPPDを`/opt/ricoh/ppd`へ展開
4. `foomatic-hash --ppd`で確認用ファイルとハッシュファイルを生成

生成物は次の場所にあります。

```text
/opt/ricoh/
├── Ricoh-Basic-PS-PPDv1.12.2.tar.gz
├── ppd/
│   ├── Readme.txt
│   ├── Ricoh-Basic_PS_B_W.ppd
│   └── Ricoh-Basic_PS_Color.ppd
└── results/
    ├── Ricoh-Basic_PS_B_W.review
    ├── Ricoh-Basic_PS_B_W.hashes
    ├── Ricoh-Basic_PS_Color.review
    └── Ricoh-Basic_PS_Color.hashes
```

ハッシュはイメージ内で生成しますが、`/etc/foomatic/hashes.d`には登録しません。
内容の確認と登録は、以下の手順でコンテナ起動後に実施します。

## ビルドとログイン

リポジトリのルートで実行します。

```sh
docker build -t foomatic-rhel9 .
docker rm -f foomatic-lab 2>/dev/null || true
docker run --name foomatic-lab -it foomatic-rhel9 bash
```

環境を確認します。

```sh
cat /etc/redhat-release
rpm -q cups-filters cups-libs
command -v foomatic-rip foomatic-hash
find /opt/ricoh -maxdepth 3 -type f -print
```

以下ではカラー版を使用します。白黒版を確認する場合は、ファイル名の
`Ricoh-Basic_PS_Color`を`Ricoh-Basic_PS_B_W`へ置き換えてください。

## 1. 抽出された値を確認する

`review`ファイルには、PPDから抽出され、ハッシュ化された値が入っています。
管理者が内容を確認してから登録してください。

```sh
less /opt/ricoh/results/Ricoh-Basic_PS_Color.review
less /opt/ricoh/results/Ricoh-Basic_PS_Color.hashes
```

`FoomaticRIPCommandLine`の値は、今回のPPDでは`review`ファイル内の`(`で
始まる行です。

```sh
grep -m1 '^(' /opt/ricoh/results/Ricoh-Basic_PS_Color.review
```

## 2. SHA-256を手動で照合する

`foomatic-hash`は、PPDから抽出・正規化した値を改行なしでSHA-256へ渡します。

```sh
value=$(grep -m1 '^(' /opt/ricoh/results/Ricoh-Basic_PS_Color.review)
digest=$(printf '%s' "$value" | sha256sum | cut -d' ' -f1)
printf '%s\n' "$digest"
grep -Fx "$digest" /opt/ricoh/results/Ricoh-Basic_PS_Color.hashes
```

`FoomaticRIPCommandLine`については、両方のコマンドで次が表示されます。

```text
954369c171dcc99287c1655bb3ec13eef930adbf5216f1101d95fc8e2aa1c436
```

`printf '%s'`を使用してください。値の末尾に改行を追加すると別のハッシュに
なります。

## 3. ハッシュ登録前の拒否を確認する

テスト用PostScriptを作成します。

```sh
cat >/tmp/input.ps <<'EOF'
%!PS-Adobe-3.0
%%Pages: 1
%%Page: 1 1
/Helvetica findfont 12 scalefont setfont
72 720 moveto (foomatic test) show
showpage
%%EOF
EOF
```

登録前に`foomatic-rip`を実行します。

```sh
foomatic-rip -v \
  --ppd /opt/ricoh/ppd/Ricoh-Basic_PS_Color.ppd \
  /tmp/input.ps \
  >/tmp/before.ps \
  2>/tmp/before.log

status=$?
printf 'exit=%s\n' "$status"
tail -20 /tmp/before.log
```

終了コード`12`と次の拒否メッセージが期待結果です。

```text
ERROR: The value of the key FoomaticRIPCommandLine is not among the allowed values
```

この実行は変換結果を`/tmp/before.ps`へ出力するだけで、プリンターへは送信しません。

## 4. 確認済みハッシュを登録する

`review`ファイルの全項目を確認した後、生成済みハッシュを登録します。

```sh
install -d -m 0755 /etc/foomatic/hashes.d
install -m 0644 \
  /opt/ricoh/results/Ricoh-Basic_PS_Color.hashes \
  /etc/foomatic/hashes.d/ricoh-color
```

登録内容を確認します。

```sh
ls -l /etc/foomatic/hashes.d/ricoh-color
grep -Fx \
  '954369c171dcc99287c1655bb3ec13eef930adbf5216f1101d95fc8e2aa1c436' \
  /etc/foomatic/hashes.d/ricoh-color
```

`FoomaticRIPCommandLine`のハッシュ1件だけでは、その後の
`FoomaticRIPOptionSetting`で拒否されます。この検証では、レビュー済みの
ハッシュファイル全体を登録します。

## 5. 登録後の成功を確認する

登録前と同じ入力を処理します。

```sh
foomatic-rip -v \
  --ppd /opt/ricoh/ppd/Ricoh-Basic_PS_Color.ppd \
  /tmp/input.ps \
  >/tmp/after.ps \
  2>/tmp/after.log

status=$?
printf 'exit=%s\n' "$status"
tail -20 /tmp/after.log
file /tmp/after.ps
wc -c /tmp/after.ps
```

期待結果は終了コード`0`と、PJL付きPostScriptファイルの生成です。

```text
exit=0
/tmp/after.ps: PJL encapsulated PostScript document text
```

この手順でも出力先は`/tmp/after.ps`であり、プリンターへの印刷要求は
送信されません。

## 6. 登録を解除する

検証後に登録を取り消す場合は、コンテナ内で次を実行します。

```sh
rm -f /etc/foomatic/hashes.d/ricoh-color
```

または、コンテナ自体を削除します。

```sh
exit
docker rm -f foomatic-lab
```

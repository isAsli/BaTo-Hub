# BaToHub

BaToHub یک مرکز مدیریت ماژولار خط فرمان برای پنل‌های پروکسی و VPN است که با Bash نوشته شده و از یک رابط تعاملی واحد کنترل می‌شود.

مستندات انگلیسی: [README.md](README.md)

## 1. نام پروژه و توضیح یک‌خطی

BaToHub یک مدیر سرور مرکزی نوشته‌شده با Bash است که پنل‌های پروکسی و VPN پشتیبانی‌شده را از یک منو تشخیص می‌دهد، تنظیم می‌کند و نگه‌داری می‌کند.

## 2. BaToHub چیست و چه چیزی نیست

چیست:

- یک مرکز مدیریت پنل‌محور با یک نقطه ورود: دستور `BaToHub`.
- مجموعه‌ای از ماژول‌های مستقل پنل که یک loader، یک پیکربندی و یک قالب پشتیبان مشترک دارند.
- ابزاری که فایل‌های خودش را در یک دایرکتوری نصب نگه می‌دارد و هیچ‌گاه پنلی را که مدیریت نمی‌کند بازنویسی نمی‌کند.
- رابط نگه‌داری برای گواهی SSL، قالب اشتراک، پشتیبان‌گیری، بروزرسانی، لاگ‌ها و بررسی یکپارچگی.

چه چیزی نیست:

- جایگزین پنل نیست. هر پنل نصب‌کننده، سرویس، دیتابیس و رابط خودش را دارد.
- کنترل پنل هاستینگ نیست و سرویس‌های نامرتبط سرور را مدیریت نمی‌کند.
- تولیدکننده لینک اشتراک نیست. اگر پنل خروجی اشتراک را از تنظیمات خودش می‌سازد، BaToHub این موضوع را اعلام می‌کند و دیتابیس آن پنل را تغییر نمی‌دهد.
- ادعا نمی‌کند نصب را غیرقابل تغییر می‌کند. کاربر root می‌تواند هر فایل محلی را تغییر دهد؛ BaToHub مانیفست یکپارچگی ثبت می‌کند و تفاوت‌ها را گزارش می‌دهد.

## 3. پنل‌های پشتیبانی‌شده

| پنل | سرویس | مسیر نصب | پورت پیش‌فرض | SSL |
| --- | --- | --- | --- | --- |
| Rebecca | `rebecca` | `/opt/rebecca` | 8000 | صدور با acme.sh در فضای وضعیت BaToHub |
| Marzban | `marzban` | `/opt/marzban` | 8000 | صدور با acme.sh، به‌روزرسانی گزینه‌های uvicorn در صورت وجود |
| PasarGuard | `pasarguard` | `/opt/pasarguard` | 8000 | صدور با acme.sh، به‌روزرسانی گزینه‌های پنل در صورت وجود |
| 3X-UI (Sanaei) | `x-ui` | `/usr/local/x-ui` | 2053 | صدور با acme.sh، استفاده از CLI پنل فقط در صورت پشتیبانی اعلام‌شده |
| VPN-UI | `vpn-ui` | `/opt/vpn-ui` | 2053 | صدور با acme.sh، دامنه یا آدرس IPv4 |

Rebecca و Marzban دو نصب جداگانه هستند، هرچند Rebecca از Marzban منشعب شده است. 3X-UI و VPN-UI هم مستقل مدیریت می‌شوند و مسیر، سرویس و وضعیت جداگانه دارند.

## 4. ابزارهای پشتیبانی‌شده

| ابزار | کاربرد | توضیح |
| --- | --- | --- |
| Foxima | رابط مدیریت PHP برای چند خانواده پنل | BaToHub پیش‌نیازها را بررسی می‌کند و نصب‌کننده رسمی را در صورت درخواست کاربر اجرا می‌کند |

## 5. امکانات

مدیریت پنل

- تشخیص خودکار پنل نصب‌شده از طریق مسیر، یونیت systemd و پورت در حال شنود.
- انتخاب پنل در اولین اجرا که همیشه از کاربر برای تأیید پنل تشخیص‌داده‌شده سؤال می‌کند.
- منوی اختصاصی هر پنل برای SSL، قالب، وضعیت، بروزرسانی، لاگ‌ها و حذف تغییرات.
- واگذاری نصب پنل به نصب‌کننده رسمی همان پنل، که با HTTPS دانلود می‌شود.

SSL

- یک دایرکتوری گواهی برای هر پنل زیر `/var/lib/batohub/panels/<panel>/ssl/`.
- صدور و تمدید با acme.sh، با ثبت دستور reload برای هر گواهی.
- مقایسه DNS پیش از صدور، با پیام‌های صریح برای رکورد نبوده و آدرس ناهمخوان.
- بررسی پورت 80 که نام سرویس در حال شنود را گزارش می‌کند، نه یک خطای کلی.
- فایل نشانه برای هر دایرکتوری گواهی، تا BaToHub هرگز به فضای گواهی پنل دیگر دست نزند.

قالب‌ها

- قالب اشتراک همراه پروژه برای پنل‌هایی که دایرکتوری قالب سفارشی مستند دارند.
- آماده‌سازی (staging) قالب برای پنل‌هایی که اشتراک را درون خود می‌سازند، با برچسب صریح.
- هر قالب جایگزین‌شده پیش از تغییر در `/var/lib/batohub/templates-backup/` کپی می‌شود.

پشتیبان‌گیری و بازیابی

- یک دستور، یک آرشیو gzip همراه فایل SHA-256 و فایل متادیتا می‌سازد.
- بازیابی ابتدا checksum را بررسی می‌کند و هر عضوی از آرشیو که در متادیتا اعلام نشده باشد را رد می‌کند.
- پیش از هر بازیابی، یک پشتیبان ایمنی ساخته می‌شود.
- چرخش پشتیبان‌ها به‌طور پیش‌فرض پنج آرشیو جدیدترین را نگه می‌دارد.

بروزرسانی

- BaToHub خود را از مخزن GitHub خودش با HTTPS بروزرسانی می‌کند.
- مسیرهای محافظت‌شده (`/etc/batohub`، `/var/lib/batohub`، `/var/log/batohub` و مسیرهای اعلام‌شده توسط کاربر) هرگز جایگزین یا حذف نمی‌شوند.
- درخت جدید با `bash -n` بررسی، رابط پنل‌ها اعتبارسنجی و مانیفست یکپارچگی بازسازی و تأیید می‌شود.
- اگر تأیید شکست بخورد، درخت قبلی از snapshot پیش از بروزرسانی بازگردانده می‌شود.

عملیات

- خلاصه وضعیت سرور، پنل، گواهی و مانیفست یکپارچگی.
- ثبت لاگ برای هر اقدام با زمان، در `/var/log/batohub/batohub.log`.
- حذف نصب که فقط فایل‌های متعلق به BaToHub را پاک می‌کند و پنل‌ها، داده‌ها و دیتابیس آن‌ها را دست‌نخورده می‌گذارد.

## 6. معماری

```
                    +-------------------------------+
                    |  /usr/local/bin/BaToHub       |
                    |  link to bin/batohub          |
                    +---------------+---------------+
                                    |
        +---------------------------+---------------------------+
        |                        core/main.sh                   |
        |  CLI flags, menus, panel detection, dispatch          |
        +---+------------------+------------------+-------------+
            |                  |                  |
   +--------v-------+  +-------v--------+  +------v--------+
   | core/panel_    |  | core/backup_   |  | core/update.sh|
   | loader.sh      |  | manager.sh     |  | self update   |
   +--------+-------+  +-------+--------+  +------+--------+
            |                  |                  |
   +--------v------------------v------------------v--------+
   |  lib/common.sh  lib/panel_helpers.sh                   |
   |  lib/ssl_helpers.sh  lib/template_helpers.sh            |
   |  lib/backup_helpers.sh                                 |
   +---------------------------+----------------------------+
                               |
              +----------------+----------------+
              |                                 |
     panels/<name>/module.sh               tools/<name>/module.sh
     panels/<name>/{ssl,templates,          tools/foxima/{install,menu}
       update,menu}/module.sh

State:     /etc/batohub        configuration and integrity manifest
           /var/lib/batohub    panel state, certificates, backups
           /var/log/batohub    logs
```

## 7. پیش‌نیازها

- Ubuntu 22.04 LTS، Ubuntu 24.04 LTS یا Debian 12.
- معماری amd64 یا arm64.
- دسترسی root برای نصب و برای عملیاتی که سرویس‌های سیستم را مدیریت می‌کنند.
- Bash نسخه 4.4 یا بالاتر، `curl`، `tar`، `gzip`، `python3`، `openssl`.
- `rsync` و `util-linux` (برای `flock`) توصیه می‌شوند؛ نصب‌کننده آن‌ها را روی Ubuntu و Debian اضافه می‌کند.
- اگر systemd وجود داشته باشد از آن استفاده می‌شود. نبود آن تشخیص داده می‌شود و گزارش می‌شود که سرویس restart نشده است.
- `acme.sh` فقط زمانی لازم است که گواهی از طریق BaToHub صادر شود.
- پنل هدف باید از قبل نصب شده باشد یا از طریق عملیات نصب BaToHub نصب شود.

## 8. نصب سریع

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/isAsli/BaTo-Hub/main/install.sh)
```

نصب‌کننده با root اجرا می‌شود، بسته‌های نبوده را روی Ubuntu و Debian نصب می‌کند، نسخه را در `/opt/batohub` کپی می‌کند، در صورت نبود `/etc/batohub` آن را می‌سازد، دستور سراسری را نصب می‌کند، رابط همه پنل‌ها و ابزارها را اعتبارسنجی می‌کند و مانیفست یکپارچگی را می‌نویسد. اجرای دوباره روی سرور نصب‌شده، پیکربندی موجود را حفظ می‌کند.

## 9. نصب دستی

```bash
git clone https://github.com/isAsli/BaTo-Hub.git
cd BaTo-Hub
sudo bash install.sh
```

سپس نصب را تأیید کنید:

```bash
BaToHub --version
BaToHub --validate
```

اگر مسیرهای پیش‌فرض مناسب نیستند:

```bash
sudo BATOHUB_SOURCE_DIR="$PWD" INSTALL_DIR=/opt/batohub GLOBAL_CMD_NAME=/usr/local/bin/BaToHub bash install.sh
```

## 10. بررسی پس از نصب

| دستور | چه چیزی تأیید می‌کند |
| --- | --- |
| `BaToHub --version` | نسخه نصب‌شده، خوانده‌شده از `/opt/batohub/VERSION` |
| `BaToHub --validate` | هر پنل و ابزار همراه پروژه بارگذاری می‌شود و توابع لازم را ارائه می‌دهد |
| `BaToHub --check` | فایل‌های روی دیسک با مانیفست یکپارچگی مطابقت دارند |
| `BaToHub --status` | وضعیت پنل، نسخه پنل، نام سرویس و دایرکتوری گواهی |
| `BaToHub --detect` | پنل‌های موجود روی این سرور |

## 11. شروع سریع

```bash
BaToHub
```

در اولین اجرا BaToHub پنل‌های پشتیبانی‌شده را جست‌وجو می‌کند. اگر پنلی پیدا شود، از شما تأیید می‌گیرد، سپس انتخاب را با مجوز 0600 در `/etc/batohub/panel.conf` ذخیره می‌کند و منوی همان پنل را باز می‌کند.

اگر پنلی پیدا نشود، BaToHub گزارش می‌دهد که پنل سازگاری نصب نیست و امکان نصب یک پنل را پیشنهاد می‌دهد، یا منوی کاهش‌یافته‌ای با نصب پنل، ابزارها، تنظیمات، بروزرسانی BaToHub و بررسی یکپارچگی باز می‌کند.

## 12. مرجع دستورات

| دستور | توضیح |
| --- | --- |
| `BaToHub` | باز کردن رابط تعاملی |
| `BaToHub --menu` | معادل اجرا بدون آرگومان |
| `BaToHub --help` | نمایش راهنما |
| `BaToHub --version` | نمایش نسخه |
| `BaToHub --list-panels` | فهرست پنل‌های پشتیبانی‌شده |
| `BaToHub --detect` | فهرست پنل‌های تشخیص‌داده‌شده روی این سرور |
| `BaToHub --status` | نمایش خلاصه وضعیت |
| `BaToHub --select-panel NAME` | ثبت پنلی که BaToHub مدیریت می‌کند |
| `BaToHub --panel NAME CMD` | اجرای یک دستور پنل بدون منو |
| `BaToHub --tools` | فهرست ابزارهای پشتیبانی‌شده |
| `BaToHub --backup` | ساخت پشتیبان در همین لحظه |
| `BaToHub --restore FILE` | بازیابی یک آرشیو پشتیبان |
| `BaToHub --update` | بروزرسانی BaToHub از GitHub |
| `BaToHub --check` | بررسی مانیفست یکپارچگی |
| `BaToHub --rebuild-integrity` | بازسازی و تأیید مانیفست یکپارچگی |
| `BaToHub --validate` | اعتبارسنجی رابط همه پنل‌ها و ابزارها |
| `BaToHub --uninstall` | حذف BaToHub با حفظ پنل‌ها و داده‌های آن‌ها |

دستورات پنل که با `--panel NAME CMD` پذیرفته می‌شوند:

| دستور | توضیح |
| --- | --- |
| `detect` | گزارش نصب‌بودن پنل |
| `version` | نمایش نسخه پنل |
| `status` | نمایش `running`، `stopped` یا `not_installed` |
| `install` | اجرای نصب‌کننده رسمی پنل |
| `uninstall` | حذف تغییرات مدیریت‌شده توسط BaToHub برای همان پنل |
| `ssl-issue` | صدور گواهی برای پنل |
| `ssl-renew` | تمدید گواهی‌های مدیریت‌شده BaToHub برای پنل |
| `ssl-status` | نمایش جزئیات گواهی |
| `template-apply` | اعمال یا آماده‌سازی قالب اشتراک |
| `template-remove` | حذف قالب مدیریت‌شده توسط BaToHub |
| `update` | اجرای بروزرسان رسمی پنل |
| `logs` | نمایش انتهای لاگ پنل |

مثال:

```bash
BaToHub --panel rebecca status
BaToHub --panel 3x-ui version
```

## 13. سیستم پنل

هر پنل یک دایرکتوری زیر `panels/` است که `panel.json` و `module.sh` و زیرماژول‌های `ssl/`، `templates/`، `update/` و `menu/` را دارد. BaToHub پنل‌ها را از فایل‌سیستم کشف می‌کند، بنابراین افزودن یک دایرکتوری برای دیده‌شدن پنل جدید کافی است.

فیلدهای `panel.json`:

| فیلد | معنا |
| --- | --- |
| `name` | نام دایرکتوری و شناسه پنل، با حروف کوچک و خط تیره |
| `display_name` | نام نمایشی در منو |
| `version` | نسخه یکپارچه‌سازی پنل، هم‌راستا با نسخه انتشار |
| `description` | یک جمله واقعی |
| `service_name` | نام یونیت systemd |
| `default_port` | پورت مورد استفاده برای تشخیص و گزارش |
| `default_path` | دایرکتوری نصب |
| `config_paths` | فایل‌های پیکربندی که BaToHub می‌تواند بخواند و پشتیبان بگیرد |
| `data_paths` | مسیرهای داده که BaToHub می‌تواند پشتیبان بگیرد |
| `database_type` | موتورهای دیتابیس پشتیبانی‌شده پنل |
| `cli_name` | ابزار خط فرمان برای نسخه و تشخیص |
| `requirements` | بسته‌های مورد انتظار یکپارچه‌سازی |
| `ssl_method` | روش مدیریت گواهی برای این پنل |
| `template_method` | روش مدیریت قالب اشتراک برای این پنل |
| `supports_bare_ip_ssl` | پشتیبانی از گواهی برای آدرس بدون دامنه |
| `supports_reseller` | داشتن حساب نمایندگی در پنل |
| `update_method` | بروزرسان رسمی مورد استفاده عملیات update |

توابع لازم ماژول:

`panel_detect`، `panel_version`، `panel_status`، `panel_install`، `panel_uninstall`، `panel_ssl_issue`، `panel_ssl_renew`، `panel_ssl_status`، `panel_ssl_remove`، `panel_template_apply`، `panel_template_remove`، `panel_template_status`، `panel_update`، `panel_logs`، `panel_menu`.

loader این متغیرها را در اختیار ماژول می‌گذارد: `PANEL_NAME`، `PANEL_DISPLAY`، `PANEL_JSON`، `PANEL_MODULE_DIR`، `PANEL_PATH`، `PANEL_SERVICE`، `PANEL_PORT`، `PANEL_CLI`، `PANEL_SSL_DIR`، `PANEL_TEMPLATE_DIR`.

نوشتن پنل جدید:

```bash
mkdir -p panels/my-panel/{ssl,templates,update,menu}
```

```json
{
  "name": "my-panel",
  "display_name": "My Panel",
  "version": "0.0.3",
  "description": "My Panel integration.",
  "service_name": "my-panel",
  "default_port": 8000,
  "default_path": "/opt/my-panel",
  "config_paths": ["/opt/my-panel/.env"],
  "data_paths": ["/var/lib/my-panel"],
  "database_type": "sqlite|postgres",
  "cli_name": "my-panel",
  "requirements": ["curl", "openssl"],
  "ssl_method": "acme.sh issuance into BaToHub state storage",
  "template_method": "panel settings; BaToHub stages template files",
  "supports_bare_ip_ssl": false,
  "supports_reseller": false,
  "update_method": "official installer"
}
```

```bash
cat >panels/my-panel/module.sh <<'MODULE'
#!/usr/bin/env bash
set -Eeuo pipefail

panel_detect() {
  [[ -d "$PANEL_PATH" ]] && return 0
  service_registered "$PANEL_SERVICE" && return 0
  return 1
}

panel_version() { "$PANEL_CLI" --version 2>/dev/null | head -n 1 || printf 'unknown\n'; }
panel_status() { panel_status_generic; }
panel_install() { panel_fetch_official_installer "https://example.invalid/install.sh" ""; }
panel_uninstall() {
  printf 'BaToHub does not remove %s.\n' "$PANEL_DISPLAY"
}
panel_logs() { panel_logs_generic "$PANEL_SERVICE" "$PANEL_PATH"; }
panel_update() { panel_submodule update && panel_update_impl; }
panel_ssl_issue() { panel_submodule ssl && ssl_issue; }
panel_ssl_renew() { panel_submodule ssl && ssl_renew; }
panel_ssl_status() { panel_submodule ssl && ssl_status; }
panel_ssl_remove() { panel_submodule ssl && ssl_remove; }
panel_template_apply() { panel_submodule templates && template_apply; }
panel_template_remove() { panel_submodule templates && template_remove; }
panel_template_status() { panel_submodule templates && template_status; }
panel_menu() { panel_submodule menu && panel_menu_impl; }
MODULE
```

سپس زیرماژول‌ها را پیاده‌سازی کنید و اجرا نمایید:

```bash
BaToHub --validate
BaToHub --panel my-panel status
```

## 14. سیستم ابزارها

هر ابزار یک دایرکتوری زیر `tools/` با `tool.json` و `module.sh` و زیرماژول‌های اختیاری `install/` و `menu/` است. ابزارها مستقل از پنل انتخابی هستند و در منوی Tools نمایش داده می‌شوند.

توابع لازم ابزار: `tool_detect`، `tool_version`، `tool_status`، `tool_install`، `tool_uninstall`، `tool_menu`.

Foxima نمونه همراه پروژه است. این ابزار یک رابط PHP است که معمولاً روی هاستینگ نصب می‌شود، بنابراین یکپارچه‌سازی:

- پیش از هر دانلود، وجود PHP و کلاینت دیتابیس را بررسی می‌کند؛
- دایرکتوری نصب را می‌پرسد و نصب در دایرکتوری‌های سیستمی را رد می‌کند؛
- نصب‌کننده رسمی را از داخل همان دایرکتوری اجرا می‌کند؛
- مسیر نصب را در `/var/lib/batohub/tools/foxima/install.path` ثبت می‌کند؛
- فقط نصبی را حذف می‌کند که BaToHub ثبت کرده باشد و پیش از حذف یک نسخه فشرده نگه می‌دارد.

## 15. مرجع پیکربندی

`/etc/batohub/batohub.conf` (مجوز 0600، ساخته‌شده توسط نصب‌کننده، هرگز توسط بروزرسانی بازنویسی نمی‌شود):

| کلید | پیش‌فرض | توضیح |
| --- | --- | --- |
| `APP_NAME` | `BaToHub` | نام پروژه در رابط |
| `APP_VERSION` | `0.0.3` | نسخه، هم‌راستا با فایل `VERSION` |
| `INSTALL_DIR` | `/opt/batohub` | فایل‌های برنامه |
| `CONFIG_DIR` | `/etc/batohub` | پیکربندی و مانیفست یکپارچگی |
| `STATE_DIR` | `/var/lib/batohub` | وضعیت پنل، گواهی‌ها، پشتیبان‌ها، قفل‌ها |
| `LOG_DIR` | `/var/log/batohub` | فایل‌های لاگ |
| `BACKUP_DIR` | `/var/lib/batohub/backups` | آرشیوهای پشتیبان |
| `BACKUP_KEEP` | `5` | تعداد آرشیوهای نگه‌داشته‌شده |
| `GITHUB_REPO` | `isAsli/BaTo-Hub` | مخزن مورد استفاده در بروزرسانی |
| `GITHUB_BRANCH` | `main` | شاخه مورد استفاده در بروزرسانی |
| `GLOBAL_CMD_NAME` | `/usr/local/bin/BaToHub` | مسیر دستور سراسری |
| `USER_MANAGED_PATHS` | خالی | مسیرهایی که بروزرسانی هرگز به آن‌ها دست نمی‌زند |

`/etc/batohub/panel.conf` (مجوز 0600، نوشته‌شده توسط BaToHub):

| کلید | توضیح |
| --- | --- |
| `PANEL` | شناسه پنل، مثلاً `rebecca` |
| `PANEL_PORT` | پورت ثبت‌شده در زمان انتخاب |
| `PANEL_PATH` | مسیر نصب ثبت‌شده در زمان انتخاب |
| `PANEL_DOMAIN` | دامنه خوانده‌شده از پیکربندی پنل در صورت وجود |
| `INSTALLED_AT` | تاریخ و ساعت انتخاب پنل |

تغییر پنل مدیریت‌شده از منوی Settings فقط `PANEL` را بازنویسی می‌کند و پنل قبلی را حذف یا تغییر نمی‌دهد.

## 16. پشتیبان‌گیری، بازیابی و ورود پشتیبان

آرشیو پشتیبان شامل:

- تمام `/etc/batohub`؛
- تمام `/var/lib/batohub`، بدون خود دایرکتوری پشتیبان‌ها؛
- تمام `/var/log/batohub`؛
- مسیرهای پیکربندی و داده اعلام‌شده پنل انتخابی در `panel.json`؛
- دایرکتوری‌های گواهی و قالب که BaToHub برای همان پنل مدیریت می‌کند؛
- فایل متادیتا `BaToHub-backup.meta` شامل نسخه BaToHub، نام پنل، نسخه پنل، زمان و فهرست مسیرها.

فایل‌ها به شکل `${BACKUP_DIR}/<timestamp>.tar.gz` با فایل کنارش `.sha256` و مجوز 0600 و مالک root ذخیره می‌شوند. چرخش، `BACKUP_KEEP` آرشیو جدیدترین را نگه می‌دارد.

بازیابی:

1. فایل SHA-256 بررسی می‌شود.
2. هر عضو آرشیو با فهرست مسیرهای متادیتا بررسی می‌شود؛ هر مسیر اعلام‌نشده باعث توقف بازیابی می‌شود.
3. یک پشتیبان ایمنی از وضعیت فعلی ساخته می‌شود.
4. آرشیو در یک دایرکتوری موقت استخراج و مسیر به مسیر کپی می‌شود. فایل‌های بیرون مسیرهای اعلام‌شده هرگز تغییر نمی‌کنند.

ورود پشتیبان (Import) یک آرشیو از مسیر دیگر را می‌پذیرد، آن را در دایرکتوری پشتیبان‌ها کپی می‌کند، در صورت نبود checksum یکی می‌سازد، آن را تأیید می‌کند و سپس از همان مسیر تراکنشی بازیابی می‌کند.

دستورات: `BaToHub --backup`، `BaToHub --restore FILE`، یا گزینه‌های Backup، Restore و Import backup در منو.

## 17. بروزرسانی خودکار

```bash
BaToHub --update
```

بروزرسانی:

1. شاخه پیکربندی‌شده را با `git` (در صورت وجود) دریافت می‌کند، در غیر این صورت `https://github.com/<repo>/archive/refs/heads/main.tar.gz` را دانلود می‌کند. هر دو مسیر از HTTPS با اعتبارسنجی گواهی استفاده می‌کنند.
2. فایل `VERSION` راه دور را با نسخه نصب‌شده مقایسه می‌کند و بازگشت به نسخه قدیمی‌تر را رد می‌کند، مگر با `--force`.
3. از دایرکتوری‌های وضعیت پشتیبان می‌گیرد و از درخت نصب snapshot می‌سازد.
4. درخت دانلودشده را پیش از هر جایگزینی با `bash -n` بررسی می‌کند.
5. فایل‌ها را همگام می‌کند و مسیرهای محافظت‌شده را دست‌نخورده می‌گذارد: `/etc/batohub/batohub.conf`، `/etc/batohub/panel.conf`، `/var/lib/batohub`، `/var/log/batohub` و هر مسیر در `USER_MANAGED_PATHS`.
6. رابط همه پنل‌ها و ابزارها را اعتبارسنجی و سپس مانیفست یکپارچگی را بازسازی و تأیید می‌کند.
7. در صورت شکست تأیید، snapshot درخت قبلی را بازمی‌گرداند.

## 18. مدل امنیتی

پیاده‌سازی‌شده:

- `set -Eeuo pipefail` در همه فایل‌های اجرایی و کوتیشن‌گذاری کامل متغیرها.
- بدون `eval`، بدون اجرای متن دانلودشده، بدون اتصال مستقیم `curl` به shell. نصب‌کننده‌ها در فایل موقت دانلود می‌شوند، اندازه آن‌ها بررسی می‌شود و به شکل `bash <file> <action>` اجرا می‌گردند.
- HTTPS با اعتبارسنجی گواهی (`--proto '=https' --tlsv1.2`) برای همه دانلودها و رد دریافت از HTTP ساده.
- اعتبارسنجی مسیر برای نام پنل، دامنه، آدرس و مقصد قالب، با رد مسیرهای بیرون دایرکتوری‌های مدیریت‌شده.
- همه فایل‌ها و دایرکتوری‌های موقت با `mktemp` ساخته می‌شوند.
- قفل فایل با `flock` برای نوشتن پیکربندی و وضعیت، و نوشتن اتمی از طریق فایل موقت در همان دایرکتوری و سپس rename.
- مجوز 0600 برای فایل‌های پیکربندی و وضعیت و 0750 برای `/etc/batohub`، `/var/lib/batohub` و `/var/log/batohub`.
- کلید خصوصی با مجوز 0600 نوشته می‌شود و هرگز چاپ نمی‌شود.
- یک دایرکتوری گواهی برای هر پنل همراه فایل نشانه مالکیت، تا هیچ پنلی فضای گواهی پنل دیگر را تصاحب نکند.
- خطوط لاگ اقدام و نتیجه را ثبت می‌کنند؛ رمز، کلید، توکن و مقادیر حساس ثبت نمی‌شوند.
- مانیفست یکپارچگی با SHA-256 برای هر فایل همراه پروژه، بررسی در زمان درخواست و پس از هر بروزرسانی.

محدودیت‌ها، صریح:

- کاربر root محلی می‌تواند هر فایلی را تغییر دهد یا حذف کند. مانیفست یکپارچگی تغییر را تشخیص می‌دهد، از آن جلوگیری نمی‌کند.
- سازوکار بروزرسانی به مخزن GitHub روی HTTPS و checksum آرشیو انتشار اعتماد می‌کند. امضای GPG در صورت ارائه کلید توسط نگه‌دارنده با `scripts/build-release.sh` پشتیبانی می‌شود؛ اگر کلیدی ارائه نشود، انتشار فقط checksum SHA-256 دارد و هیچ ادعای امضایی مطرح نمی‌شود. جزئیات در [SECURITY.fa.md](SECURITY.fa.md).
- acme.sh به‌عنوان کلاینت گواهی مورد اعتماد است و BaToHub آن را بازرسی نمی‌کند.
- پنل‌ها با نصب‌کننده رسمی خودشان نصب می‌شوند، با HTTPS دانلود و همان‌گونه که ارائه شده‌اند اجرا می‌شوند. BaToHub آن کد را بازبینی نمی‌کند.
- BaToHub آزمون نفوذ خودکار انجام نمی‌دهد و ادعایی در این مورد ندارد.
- اگر پنل نقطه یکپارچه‌سازی مستندی نداشته باشد، BaToHub این را گزارش می‌کند و متوقف می‌شود، نه اینکه ساختار دیتابیس را حدس بزند.

## 19. لاگ و عیب‌یابی

لاگ‌ها با زمان روی هر خط در `/var/log/batohub/batohub.log` ثبت می‌شوند. بخش Logs در منوی سرور هشتاد خط آخر را نشان می‌دهد.

موارد رایج:

| نشانه | چه چیزی را بررسی کنید |
| --- | --- |
| `certificate issuance failed` | رکورد A دامنه، آزاد بودن پورت 80 و خروجی acme.sh در لاگ |
| `Port 80 is already in use` | پیام، سرویس در حال شنود را نام می‌برد؛ آن سرویس را متوقف کنید یا گواهی را با DNS-01 بیرون BaToHub صادر کنید |
| `Service X is not registered with systemd` | پنل نصب است اما یونیت systemd ندارد، بنابراین چیزی restart نشده است |
| `integrity: manifest missing` | `BaToHub --rebuild-integrity` را اجرا کنید |
| `integrity: mismatched files detected` | `BaToHub --check` فایل‌های متفاوت با مانیفست را نشان می‌دهد |
| پنل تشخیص داده نمی‌شود | مسیر، یونیت systemd و پورت در حال شنود را با `panel.json` مقایسه کنید |
| نسخه راه دور قدیمی‌تر است | بازگشت به نسخه قدیمی به‌طور طراحی‌شده رد می‌شود؛ تنها در صورت قصد قبلی از `--force` استفاده کنید |

دستورات مفید:

```bash
BaToHub --status
BaToHub --check
BaToHub --validate
BaToHub --panel rebecca logs
tail -n 200 /var/log/batohub/batohub.log
```

## 20. حذف نصب

```bash
BaToHub --uninstall
```

حذف‌کننده فهرست دقیق آنچه پاک می‌شود را نشان می‌دهد، عبارت تأیید می‌خواهد و فقط این‌ها را پاک می‌کند:

- `/opt/batohub`
- `/etc/batohub`
- `/var/lib/batohub`
- `/var/log/batohub`
- لینک دستور سراسری، و فقط اگر به `/opt/batohub/bin/batohub` اشاره کند

آرشیوهای پشتیبان می‌توانند به‌جای حذف به `/var/backups/batohub-<timestamp>` منتقل شوند. پنل‌ها، دیتابیس‌ها، پیکربندی آن‌ها و گواهی‌های بیرون از فضای وضعیت BaToHub هرگز حذف نمی‌شوند. `bin/uninstall --yes` برای اتوماسیون، پرسش را رد می‌کند و `--keep-backups` بدون پرسش، آرشیوها را نگه می‌دارد.

## 21. مجوز

BaToHub تحت مجوز GNU General Public License نسخه 3 منتشر می‌شود. متن کامل در [LICENSE](LICENSE) است. متن مجوز بدون تغییر استفاده شده است: بدون شرط اضافه، بدون استثنا و بدون مجوز دوگانه.

## 22. سیاست تغییر و بازتوزیع

هر استفاده، تغییر، انشعاب (fork)، اعطای زیرمجوز یا بازتوزیع باید کاملاً با GPL-3.0 سازگار باشد و باید اعلان کپی‌رایت اصلی، نام پروژه BaToHub و نشانی مخزن اصلی را حفظ کند. نسخه‌های اختصاصی یا مالکانه تحت این مجوز مجاز نیست. هر کسی که نسخه اختصاصی یا خصوصی نیاز دارد باید از طریق کانال پشتیبانی زیر تماس بگیرد.

## 23. پشتیبانی و ارتباط

پشتیبانی، گزارش خطا و درخواست امکانات: **@DatPHP**

پیش از درخواست کمک، این اطلاعات را همراه داشته باشید:

- خروجی `BaToHub --version`، `BaToHub --status` و `BaToHub --check`؛
- نام و نسخه پنل؛
- دستور دقیقی که خطا داد و پیام خطا؛
- خطوط آخر `/var/log/batohub/batohub.log`.

کلید خصوصی، رمز عبور و توکن را در گزارش قرار ندهید.

دامنه پشتیبانی در [SUPPORT.fa.md](SUPPORT.fa.md)، روش ارسال تغییرات در [CONTRIBUTING.fa.md](CONTRIBUTING.fa.md)، گزارش آسیب‌پذیری در [SECURITY.fa.md](SECURITY.fa.md) و انتظارات رفتاری در [CODE_OF_CONDUCT.fa.md](CODE_OF_CONDUCT.fa.md) آمده است. تغییرات در [CHANGELOG.md](CHANGELOG.md) ثبت می‌شود.

## 24. اعتبار و کپی‌رایت

BaToHub توسط پروژه BaToHub توسعه و نگه‌داری می‌شود. کپی‌رایت متعلق به مشارکت‌کنندگان پروژه است و تحت شرایط GPL-3.0 توزیع می‌شود. نام پنل‌ها، نام پروژه‌ها و علائم تجاری متعلق به صاحبان آن‌هاست و BaToHub وابستگی به آن‌ها ندارد.

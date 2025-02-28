Описание работы скрипта :

Этот скрипт является утилитой для управления резервным копированием домашних директорий пользователей в Linux-системе. Он предоставляет главное меню с семью опциями, включая создание, восстановление и удаление бэкапов различными способами: локально, на удалённом SSH-сервере и на сетевой папке через подменю.

При запуске скрипт автоматически проверяет наличие необходимых утилит (tar, du, df, lsof, ssh, scp, sshpass, mount, cifs-utils) и устанавливает их через apt, если они отсутствуют. Это обеспечивает готовность системы к выполнению всех функций.

Создание локального бэкапа пользователей (опция 1) начинается с поиска пользователей с UID >= 1000 и домашними директориями в /home. Скрипт выводит список пользователей с примерным размером бэкапов, рассчитанным через du с учётом сжатия. Пользователь выбирает одного или всех для бэкапа. Перед этим проверяются открытые файлы в директории с помощью lsof, и, если они есть, выводятся их имена и процессы (имя и PID) с предложением убить их через kill -9. Бэкап создаётся в виде архива .tar.gz в папке /opt/packhomebackupmaster/backups.

Создание бэкапа на SSH-сервер (опция 2) требует ввода имени сервера, логина, пароля и пути на сервере. Скрипт проверяет подключение через sshpass и ssh с автоматическим принятием ключа сервера, затем создаёт временный локальный бэкап и отправляет его на сервер через scp, удаляя временный файл после успеха. Проверка открытых файлов также выполняется.

Опция 3 открывает подменю для работы с сетевой папкой. В подменю есть два пункта: создание бэкапа на сетевую папку и восстановление с неё. Для подключения запрашиваются IP-адрес сервера, путь к сетевой папке, логин и пароль (опционально). Сетевая папка монтируется через mount с типом cifs (Samba) в /mnt/network_backup. При создании бэкапа процесс аналогичен локальному, но архивы сохраняются в смонтированную папку. При восстановлении скрипт сканирует бэкапы в этой папке, позволяет выбрать один или все, восстанавливает их и проверяет наличие пользователя в системе. После завершения папка размонтируется через umount.

Восстановление локального бэкапа (опция 4) сканирует папку бэкапов, выводит список архивов с именами пользователей и датами, позволяет выбрать один или все. Перед восстановлением проверяется свободное место на диске через df. Архив извлекается в /home/, и если пользователь не существует, предлагается его создать через useradd с возможностью установки пароля через passwd.

Восстановление бэкапа с SSH-сервера (опция 5) запрашивает те же данные для подключения, получает список бэкапов через ssh, скачивает выбранный архив во временный файл через scp, восстанавливает его и удаляет временный файл. Выполняются проверки свободного места и создания пользователя.

Удаление локальных бэкапов (опция 6) показывает список бэкапов в локальной папке и позволяет выбрать один или несколько для удаления.

Выход (опция 7) завершает работу скрипта.

На каждом этапе можно вернуться в главное меню или подменю, выбрав q, что делает скрипт интерактивным и гибким.

Description of the script :

This script is a utility for managing backups of users' home directories in a Linux system. It offers a main menu with seven options, including creating, restoring, and deleting backups in various ways: locally, on a remote SSH server, and on a network share via a submenu.

Upon startup, the script automatically checks for required tools (tar, du, df, lsof, ssh, scp, sshpass, mount, cifs-utils) and installs them via apt if they are missing. This ensures the system is ready for all operations.

Creating a local user backup (option 1) begins by finding users with UID >= 1000 and home directories in /home. The script lists users with an estimated backup size, calculated using du with compression factored in. The user selects one or all for backup. It checks for open files in the directory using lsof, and if any are found, it displays their names and processes (name and PID), offering to kill them with kill -9. The backup is created as a .tar.gz archive in /opt/packhomebackupmaster/backups.

Creating a backup on an SSH server (option 2) requires entering the server name, login, password, and path on the server. The script verifies the connection using sshpass and ssh with automatic server key acceptance, creates a temporary local backup, sends it to the server via scp, and deletes the temporary file upon success. It also checks for open files.

Option 3 opens a submenu for network share operations, with two choices: creating a backup on a network share and restoring from it. Connection details are requested: server IP, share path, login, and password (optional). The network share is mounted using mount with cifs type (Samba) at /mnt/network_backup. For backup creation, the process mirrors the local one, but archives are saved to the mounted share. For restoration, it scans backups in the mounted folder, allows selection of one or all, restores them, and checks user existence. The share is unmounted with umount afterward.

Restoring a local user backup (option 4) scans the backup directory, lists archives with user names and dates, and allows selection of one or all. It checks free disk space using df before proceeding. The archive is extracted to /home/, and if the user doesn’t exist, it offers to create them with useradd and set a password with passwd.

Restoring a backup from an SSH server (option 5) requests the same connection details, retrieves the backup list via ssh, downloads the selected archive to a temporary file via scp, restores it, and deletes the temporary file. It performs free space and user creation checks.

Deleting local backups (option 6) displays a list of local backups and allows selection of one or multiple for deletion.

Exiting (option 7) terminates the script.

At each step, the user can return to the main menu or submenu by selecting q, making the script interactive and flexible.

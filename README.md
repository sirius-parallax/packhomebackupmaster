Описание работы скрипта :
Этот скрипт представляет собой утилиту для управления резервным копированием (бэкапом) домашних директорий пользователей в Linux-системе. Он предоставляет меню с шестью опциями, которые позволяют создавать, восстанавливать и удалять бэкапы как локально, так и на удалённом сервере через SSH. Вот как он работает:

Создание локального бэкапа пользователей:
Скрипт находит всех пользователей с UID >= 1000 и домашними директориями в /home.
Выводит список пользователей с примерным размером их бэкапов (оценка через du с учётом сжатия).
Позволяет выбрать одного пользователя или всех для бэкапа.
Перед созданием бэкапа проверяет, заняты ли файлы в директории с помощью lsof. Если да, выводит список файлов и процессов (имя и PID), предлагая убить их (kill -9) или продолжить без изменений.
Создаёт архив .tar.gz в локальной папке /opt/packhomebackupmaster/backups.
Создание бэкапа пользователей на SSH-сервер:
Запрашивает данные для подключения: имя сервера, логин, пароль и путь на сервере.
Проверяет подключение через sshpass и ssh с автоматическим принятием ключа сервера (-o StrictHostKeyChecking=no).
Создаёт локальный временный бэкап, затем отправляет его на сервер через scp и удаляет временный файл.
Также проверяет занятые файлы перед бэкапом.
Восстановление локального бэкапа пользователей:
Сканирует локальную папку бэкапов и выводит список доступных архивов с именами пользователей и датой создания.
Позволяет выбрать один бэкап или все для восстановления.
Проверяет свободное место на диске перед восстановлением с помощью df.
Извлекает архив в /home/<username> и проверяет, существует ли пользователь. Если нет, предлагает создать его (useradd) и установить пароль (passwd).
Восстановление бэкапа с SSH-сервера:
Запрашивает данные подключения и получает список бэкапов с сервера через ssh.
Скачивает выбранный бэкап во временный файл через scp, восстанавливает его и удаляет временный файл.
Выполняет те же проверки свободного места и создания пользователя.
Удаление локальных бэкапов:
Выводит список локальных бэкапов и позволяет выбрать один или несколько для удаления.
Выход:
Завершает выполнение скрипта.
Дополнительные функции:

Автоматическая установка зависимостей (tar, du, df, lsof, ssh, scp, sshpass) через apt, если они отсутствуют.
Возможность возврата в главное меню (q) на каждом этапе.

Description of the script (in English):
This script is a utility for managing backups of users' home directories in a Linux system. It provides a menu with six options to create, restore, and delete backups both locally and on a remote server via SSH. Here’s how it works:

Create Local User Backup:
The script finds all users with UID >= 1000 and home directories in /home.
Displays a list of users with an estimated backup size (calculated using du with compression factored in).
Allows selection of one user or all for backup.
Before creating the backup, it checks for open files in the directory using lsof. If found, it lists the files and processes (name and PID), offering to kill them (kill -9) or proceed without changes.
Creates a .tar.gz archive in the local directory /opt/packhomebackupmaster/backups.
Create User Backup on SSH Server:
Prompts for connection details: server name, login, password, and path on the server.
Verifies the connection using sshpass and ssh with automatic acceptance of the server key (-o StrictHostKeyChecking=no).
Creates a temporary local backup, sends it to the server via scp, and removes the temporary file.
Also checks for open files before backup.
Restore Local User Backup:
Scans the local backup directory and lists available archives with user names and creation dates.
Allows selection of one backup or all for restoration.
Checks free disk space before restoration using df.
Extracts the archive to /home/<username> and checks if the user exists. If not, it offers to create the user (useradd) and set a password (passwd).
Restore User Backup from SSH Server:
Prompts for connection details and retrieves the list of backups from the server via ssh.
Downloads the selected backup to a temporary file via scp, restores it, and deletes the temporary file.
Performs the same free space and user creation checks.
Delete Local Backups:
Displays a list of local backups and allows selection of one or multiple backups for deletion.
Exit:
Terminates the script execution.
Additional Features:

Automatic installation of dependencies (tar, du, df, lsof, ssh, scp, sshpass) via apt if they are missing.
Option to return to the main menu (q) at each step.

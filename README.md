Описание работы скрипта :

Этот скрипт представляет собой утилиту для управления резервным копированием (бэкапом) домашних директорий пользователей в Linux-системе. Он предоставляет меню с шестью опциями, которые позволяют создавать, восстанавливать и удалять бэкапы как локально, так и на удалённом сервере через SSH.

Создание локального бэкапа пользователей начинается с того, что скрипт находит всех пользователей с UID >= 1000 и домашними директориями в /home. Затем он выводит список пользователей с примерным размером их бэкапов, который оценивается через du с учётом сжатия. Пользователь может выбрать одного или всех для бэкапа. Перед созданием бэкапа скрипт проверяет с помощью lsof, заняты ли файлы в директории, и, если да, показывает список файлов и процессов (имя и PID), предлагая убить их командой kill -9 или продолжить без изменений. Бэкап создаётся в виде архива .tar.gz в локальной папке /opt/packhomebackupmaster/backups.

Создание бэкапа пользователей на SSH-сервер требует ввода данных для подключения: имени сервера, логина, пароля и пути на сервере. Скрипт проверяет подключение через sshpass и ssh с автоматическим принятием ключа сервера (-o StrictHostKeyChecking=no). Затем он создаёт временный локальный бэкап, отправляет его на сервер через scp и удаляет временный файл. Проверка занятых файлов также выполняется перед бэкапом.

Восстановление локального бэкапа пользователей начинается со сканирования локальной папки бэкапов. Скрипт выводит список доступных архивов с именами пользователей и датой создания, позволяя выбрать один бэкап или все для восстановления. Перед этим он проверяет свободное место на диске с помощью df. Архив извлекается в /home/<username>, после чего скрипт проверяет, существует ли пользователь. Если нет, он предлагает создать его с помощью useradd и установить пароль через passwd.

Восстановление бэкапа с SSH-сервера требует ввода тех же данных подключения. Скрипт получает список бэкапов с сервера через ssh, позволяет выбрать один или все, скачивает выбранный бэкап во временный файл через scp, восстанавливает его и удаляет временный файл. Выполняются те же проверки свободного места и создания пользователя.

Удаление локальных бэкапов позволяет просмотреть список бэкапов в локальной папке и выбрать один или несколько для удаления.

Выход завершает выполнение скрипта.

Дополнительные функции включают автоматическую установку зависимостей (tar, du, df, lsof, ssh, scp, sshpass) через apt, если они отсутствуют, и возможность возврата в главное меню (q) на каждом этапе.

Description of the script :

This script is a utility for managing backups of users' home directories in a Linux system. It provides a menu with six options to create, restore, and delete backups both locally and on a remote server via SSH.

Creating a local user backup starts with the script finding all users with UID >= 1000 and home directories in /home. It then displays a list of users with an estimated backup size, calculated using du with compression factored in. The user can select one or all for backup. Before creating the backup, the script checks for open files in the directory using lsof, and if any are found, it lists the files and processes (name and PID), offering to kill them with kill -9 or proceed without changes. The backup is created as a .tar.gz archive in the local directory /opt/packhomebackupmaster/backups.

Creating a user backup on an SSH server requires entering connection details: server name, login, password, and path on the server. The script verifies the connection using sshpass and ssh with automatic server key acceptance (-o StrictHostKeyChecking=no). It creates a temporary local backup, sends it to the server via scp, and deletes the temporary file. Open file checks are also performed before the backup.

Restoring a local user backup begins with scanning the local backup directory. The script lists available archives with user names and creation dates, allowing the user to select one or all for restoration. It checks free disk space using df before proceeding. The archive is extracted to /home/<username>, and the script checks if the user exists. If not, it offers to create the user with useradd and set a password with passwd.

Restoring a backup from an SSH server requires entering the same connection details. The script retrieves the list of backups from the server via ssh, allows selection of one or all, downloads the selected backup to a temporary file via scp, restores it, and deletes the temporary file. It performs the same free space and user creation checks.

Deleting local backups displays a list of local backups and allows the user to select one or multiple backups for deletion.

Exiting terminates the script execution.

Additional features include automatic installation of dependencies (tar, du, df, lsof, ssh, scp, sshpass) via apt if they are missing, and the ability to return to the main menu (q) at each step.

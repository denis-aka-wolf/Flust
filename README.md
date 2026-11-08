# Flust

Flust — это визуальный редактор Flutter-виджетов для VS Code. Исходный код на Dart остаётся единственным источником истины.

## Структура репозитория

- `apps/vscode` — расширение для VS Code и редактор на основе Webview.
- `packages/visual-editor` — переиспользуемые модули пользовательского интерфейса визуального редактора.
- `tools/analyzer` — анализатор AST для Dart и протокол обмена данными в формате JSON Lines.
- `examples/flutter_app` — пример приложения на Flutter.
- `docs` — документация по архитектуре и протоколу взаимодействия компонентов.

## Необходимые компоненты

Перед началом работы установите:

- Node.js 24.22.1 (LTS) и npm.
- VS Code.
- Dart SDK (также входит в состав Flutter SDK).

## Запуск расширения

1. Откройте репозиторий `flust/` в VS Code.
2. Откройте терминал и выполните команду:

   ```sh
   cd apps/vscode && npm install && npm run compile
   ```

3. Нажмите `F5`, чтобы запустить среду разработки расширений — Extension Development Host.
4. Откройте файл `.w.dart` в примере проекта или откройте любой файл Dart и выполните команду **Flust: Open in Flust**.

Расширение ищет анализатор по пути `tools/analyzer/bin/flust_analyzer.dart` относительно открытой рабочей области.

Если запустить анализатор не удаётся, редактор выводит соответствующее сообщение и продолжает работу, используя упрощённое резервное представление.

## Запуск анализатора

Выполните следующие команды в терминале:

```sh
cd tools/analyzer
dart pub get
dart analyze
```

Если ошибок нет, запустить анализатор можно так:

```sh
dart run bin/flust_analyzer.dart
```

Анализатор использует протокол JSON Lines: каждый запрос передаётся в виде отдельной строки JSON, и каждый ответ возвращается в виде отдельной строки JSON.

Проверь его можно тестовым запросом (анализатор не должен быть запущен):

```sh
@'
{"id":"test-1","method":"parse","uri":"file:///test.dart","source":"Widget build(BuildContext context) => const Text('Hi');"}
'@ | dart run bin/flust_analyzer.dart
```

Ожидаемый результат содержит "id":"test-1" и "ok":true.

## Текущий этап разработки

На данном этапе создана базовая инфраструктура проекта, включающая:

- точку входа расширения VS Code;
- пользовательский редактор с поддержкой Custom Editor API;
- команду `Open in Flust` для открытия файлов в редакторе Flust;
- механизм взаимодействия с анализатором;
- протокол обмена данными JSON Lines;
- начальную реализацию конвейера преобразования AST в дерево виджетов.

Это ранняя стадия разработки, а не готовый к промышленному использованию визуальный конструктор.

Редактирование исходного кода из визуального интерфейса и полноценный предпросмотр Flutter-приложений запланированы для последующих этапов разработки.

## Диагностика и логи Flust

Откройте **View → Output** и выберите канал **Flust**. Также доступны команды **Flust: Show Logs** и **Flust: Clear Logs** из Command Palette. Кнопка **Show logs** находится в заголовке визуального редактора.

Лог ведётся в структурированном JSON Lines формате. Каждая запись содержит `timestamp`, `level`, `component`, `stage`, `message` и, когда применимо, `requestId`, длительность и диагностические данные. Отдельно фиксируются запуск Dart-процесса, stdout/stderr, отправка и получение JSON-RPC-подобных сообщений JSON Lines, тайм-ауты и построение модели.

## Поиска Dart SDK.

Flust ищет dart.exe в следующем порядке:
1. Собственная настройка flust.dartPath.
2. dart.sdkPath из расширения Dart.
3. dart.flutterSdkPath из Flutter.
4. Системный PATH.

Если SDK не найден, Flust покажет конкретную инструкцию по исправлению.

### Как настроить
В VS Code откройте settings.json и добавьте:
```JSON
{
  "flust.dartPath": "F:\\flutter\\bin\\cache\\dart-sdk\\bin\\dart.exe"
}
```

Путь выше примерный. Укажите реальное расположение своего dart.exe.

Чтобы узнать его:
```bash
where.exe dart
```

Затем пересобрать расширение:

```bash
cd F:\Dart\Flust\apps\vscode
npm install
npm run compile
```

После этого уже можно перезапускать Extension Development Host.

## Скрипты установки Flust

Файлы:
  setup_flust.ps1  Реализация для PowerShell (основная логика установщика)
  setup_flust.bat  Запускатель для Windows CMD
  setup_flust.sh   Запускатель для Git Bash / MinGW

Порядок обнаружения SDK:
  1. Переменная окружения FLUTTER_ROOT
  2. Параметр dart.flutterSdkPath в пользовательских настройках VS Code / VS Code Insiders
  3. Команда where.exe flutter
  4. Команда where.exe dart

Установщик ищет непосредственно исполняемый файл dart.exe, отдавая
предпочтение версии из комплекта Flutter:
  bin\cache\dart-sdk\bin\dart.exe

Файл dart.bat не используется в качестве исполняемого файла анализатора,
поскольку его непосредственный запуск через Node.js может завершиться
ошибкой в Windows.

Установщик обновляет существующие файлы настроек VS Code и VS Code Insiders.
Если ни один из них не найден, создаётся файл настроек обычного VS Code.

Все существующие настройки сохраняются. При этом файл должен содержать
корректный JSON. Комментарии формата JSONC, поддерживаемые VS Code,
этой реализацией PowerShell не поддерживаются.

Запуск из корневой папки проекта или из папки со скриптами:
  PowerShell: .\setup_flust.ps1
  CMD:        setup_flust.bat
  Git Bash:   ./setup_flust.sh

### Расположение файлов настроек

VS Code:
   %APPDATA%\Code\User\settings.json

VS Code Insiders:
   %APPDATA%\Code - Insiders\User\settings.json

Например, для пользователя Windows с именем Mark:
  C:\Users\Mark\AppData\Roaming\Code\User\settings.json
  C:\Users\Mark\AppData\Roaming\Code - Insiders\User\settings.json

Если ни один из файлов настроек не существует, установщик
создаёт стандартный файл VS Code:
  %APPDATA%\Code\User\settings.json
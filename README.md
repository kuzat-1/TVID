# TANHO (TVID) — видео без политики

Мобильное приложение-агрегатор видео на базе **VK Video**.
Главная лента — только горизонтальные видео, клипы — только в Reels.
Без YouTube, без политики (фильтр политического контента на клиенте и сервере).

- Пакет: `su.layn.app`
- Текущая версия: **1.3.4+34**
- Ветки репозитория: `main` — приложение (Flutter), `backend` — сервер (Node.js)

## Возможности

- Главная лента: все видео из базы, порции по 50 + бесконечный скролл
- Reels: только вертикальные видео, свайпы вверх/вниз
- Поиск по каталогу (типизированный запрос, дебаунс 600 мс)
- Рекомендации: сортировка по интересам пользователя (что смотрит — то выше), иначе перемешивание
- История просмотров (30 последних, локально)
- «Предложить видео» — отправка ссылки VK на модерацию
- «Пригласи друга» — шаринг ссылки на Play Market (баннер закрывается крестиком навсегда)
- Встроенная админка (пароль, открывается долгим тапом по логотипу 3 сек): дашборд, видео (скрыть/удалить/обновить обложку/добавить), настройки
- Реклама: Яндекс (лента/Reels/плеер) и/или свой HTML (плеер/открытие/лента/Reels)
- Push-уведомления: **отложены** (не реализованы)

## Стек

| Слой | Инструменты |
|---|---|
| Приложение | Flutter 3 / Dart, `flutter_inappwebview` (VK-плеер через `video_ext.php` + JS API), `shared_preferences`, `permission_handler` |
| Реклама | `yandex_mobileads`, свой HTML через WebView |
| Облако | `firebase_core`, `cloud_firestore` (блэклист, кастом, настройки, статистика) |
| Шаринг | `share_plus`, `url_launcher` |
| Сервер | Node.js + Express, `yt-dlp` (резолв/синхронизация VK), `axios` |
| API VK | Service Token (`video.get`, `wall.get`, `groups.getById`), cookies.txt для клипов каналов |
| Админка сервера | SPA в `public/admin` (дашборд, видео, источники, синхронизация, настройки, cookies) |

## Фирменные цвета

| Токен | HEX | Назначение |
|---|---|---|
| `bgColor` | `#0D0E12` | фон |
| `surfaceColor` | `#1A1C23` | карточки |
| `primaryPurple` | `#5B41D9` | акцент, градиенты, кнопки |
| `secondaryPurple` | `#8C7AE6` | акцент светлый, свечения |
| `navIconIdle` | `#8E8E93` | иконки навигации |
| `textPrimary` | `#FFFFFF` | заголовки |
| `textSecondary` | `#A4B0BE` | подзаголовки |
| `textMuted` | `#747D8C` | мелкий текст |
| `placeholderPurple` | `#241D4B` | плейсхолдеры |
| фон приложения | `#0D0D0D → #151027 → #0D0D0D` | градиент сверху вниз |

## Как устроена раздача видео (правила сервера)

Правила живут на сервере, поэтому действуют для любой версии приложения:

- `/api/catalog` без поискового слова — только **горизонтальные** (главная лента)
- `q=new` / `q=popular` — сортировки (новые / популярные), тоже без вертикалей
- Поиск с текстом — ищет по **всему** каталогу, включая клипы
- `/api/catalog/reels` — только **вертикальные**
- Обложки проверяются (HEAD-запрос, `image/*`), битые отсекаются; в приложении для таких — карточка «Нажми, чтобы запустить»

## Синхронизация контента

- Канал: обычные видео (`video.get`) + стена (`wall.get filter=video`) + клипы (yt-dlp с cookies)
- Плейлисты клипов: `vk.ru/clips/playlist/-ID_N`
- Кнопка «Синхронизировать» есть у каждого источника — повторы пропускаются
- Cookies VK: Настройки админки → поле/файл `cookies.txt` (расширение «Get cookies.txt LOCALLY»)

## Сборка

```bash
flutter pub get
flutter analyze
flutter build appbundle --release   # AAB для Play Console
flutter build apk --release         # универсальный APK
```

Подпись релиза: `android/key.properties` + `android/keystore/` — **не хранятся в репозитории**.
`version` в `pubspec.yaml` (`1.3.5+35` и выше для следующего релиза — код версии обязан расти для Play Console).

## Структура

```
lib/main.dart            # всё приложение (экраны, плеер, админка)
android/app/             # applicationId su.layn.app, targetSdk 36
public/admin/ (ветка backend)  # веб-админка: public/admin/index.html, app.js
src/routes/  (ветка backend)   # catalog, sync, suggest, vk, admin, stream
src/services/(ветка backend)   # vkParseService (yt-dlp, cookies, обложки)
```

## Контакты/ссылки

- API: `https://kuzat.ru`
- DMCA: `https://kuzat.ru/dmca`, Privacy: `https://kuzat.ru/privacy`
- Поделиться: `https://play.google.com/store/apps/details?id=su.layn.app`

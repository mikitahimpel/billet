# Игры для пар: что популярно и что встроить в Nooki

> Собрано 5 ноября 2026. Публичных цифр по отдельным играм внутри парных приложений нет: ни Paired,
> ни Widgetable, ни GamePigeon не публикуют статистику по режимам. «Популярность» ниже — это то,
> сколько крупных приложений держат формат и как часто его называют в обзорах и опросах, а не
> измеренные запуски. Большинство обзоров написаны самими вендорами.

## 1. Что держат на рынке

| Формат | У кого есть | Сигнал популярности |
|---|---|---|
| **«Насколько ты меня знаешь»** / совпадёте ли ответы | Paired (couple games), Couple Joy, Lovelee (In sync, Couples quiz), Agapé, десятки отдельных приложений «How Well Do You Know Me» | Самый частый формат во всех списках. У Agapé виральность дало одновременное раскрытие ответов: пары снимали реакцию для TikTok |
| **Would you rather / This or that** | Couple Joy, Lovelee, Couple App Would You Rather, Foreplay Game | Почти в каждом наборе, самый дешёвый по контенту |
| **Who's more likely / Never have I ever** | Couple Joy, Foreplay Game, TikTok-форматы от авторов | Тренд в TikTok, но как формат авторов, а не функция приложений |
| **Truth or dare, «острые» игры** | True Talk, Smush, Spicy Challenge, Paired (17+) | Отдельная большая ниша, почти всегда за пейволлом и с рейтингом 17+ |
| **Пошаговая классика** (8 ball, морской бой, крестики-нолики, Connect 4, шашки) | GamePigeon (iMessage), Lovelee (Tic tac toe, Connect 4) | GamePigeon — главная «игра на двоих в телефоне»; в школьных опросах 8 Ball чаще всего называют любимой |
| **Словесные** (Anagrams, Word Hunt, Wordle-подобные) | GamePigeon, Lovelee (Anagrams, Secret word, Word net), Words With Friends, Letterpress | Words With Friends называют исходной асинхронной игрой для пар; Anagrams и Word Hunt — среди самых залипательных в GamePigeon |
| **Нарисуй и угадай** | Draw Something (50 млн загрузок за два месяца на пике), Gartic Phone (в основном компании) | Доказанный хит на двоих; в парных приложениях почти никто не делает, есть только дудлы на виджете |
| **Кооператив вокруг общего мира** | Lovelee (Laundry day, рыбалка), Widgetable (уход за питомцем) | У Widgetable игры — слабое место: в отзывах просят мини-игры, существующие ругают за «много времени, мало награды» |

Выводы:
- В топе форматы про **знание друг друга**, а не механика. Это ядро всех крупных парных приложений.
- Работает только то, что играется **асинхронно**: партнёр редко онлайн одновременно. Lovelee решает это ботом-«чайкой».
- Никто не связывает игры с питомцем и миром. У Widgetable питомец без игр, у Lovelee игры отдельно от кораблика. Здесь у Nooki пустое место.

## 2. Что уже есть у Nooki и на что опираться

- **Игры с Mochi:** перо, лазер, мяч, клубок (`CatToy`), трюки. Игра влияет на мозг кота: игривость растёт, неделя без игр её сбрасывает ([cat-brain.md](../../../../docs/cat-brain.md)).
- **Журнал кота:** `GamePlayed { game: CatGameId, score, won }` уже есть в контрактах; `CatGameId` — свободная строка `[a-z0-9-]`, новую игру можно добавить без смены схемы.
- **Монеты:** победа 10, поражение 3, лимит 40 в день, начисляет комната ([payments.md](../../../../docs/payments.md)).
- **Inbox:** строка «партнёр сыграл» уже рендерится из `CatGamePlayed` ([activity.md](../../../../docs/activity.md)).
- **Живые штрихи:** комната ретранслирует `StrokeBegin/Points/End` по сокету, есть компактные штрихи под 3 КБ для пуша и виджета.
- **Вопрос дня** уже спроектирован отдельно ([engagement-concept.md](../engagement-concept.md#31-ежедневный-ритуал-вопрос-дня)), поэтому ниже он не считается игрой.

## 3. Кандидаты для Nooki

Оценка: **спрос** (по таблице выше), **связь с Mochi и комнатой**, **стоимость** при текущей инфраструктуре.

| # | Игра | Как это у нас | Спрос | Связь | Стоимость |
|---|---|---|---|---|---|
| 1 | **«Угадай, что ответит партнёр»** | 5 вопросов: каждый отвечает за себя и угадывает ответ другого. Раскрытие, когда ответили оба; Mochi объявляет совпадения. Режим «This or that» — те же вопросы с двумя вариантами | высокий | средняя | средняя: таблица ответов в `PairRoom`, пуш «партнёр ответил», контент на ru/en |
| 2 | **«Нарисуй — угадай»** | Один рисует загаданное слово существующим холстом, отправляет как записку; другой угадывает из букв. Угадал — оба получают монеты, рисунок можно повесить в комнате | высокий (Draw Something) | высокая: это и есть ядро приложения, записки-рисунки | низкая: холст, штрихи и доставка уже есть; нужен словарь и экран угадывания |
| 3 | **Кооп с Mochi вдвоём** | Когда оба в комнате, у каждого своя игрушка (перо и лазер), Mochi бегает между ними; общий счёт ловли | средний (кооп Lovelee) | максимальная | средняя: синхронизация положения игрушек по сокету, как штрихи |
| 4 | **Пошаговая классика** | Крестики-нолики, Connect 4, морской бой на столе в комнате. Ход — кадр в комнате и пуш. Если партнёр молчит, ходит Mochi | высокий (GamePigeon) | низкая, пока игра не в комнате | средняя: состояние партии в `PairRoom`, по экрану на игру |
| 5 | **Словесная на общем сиде** | Anagrams или Word Hunt: оба получают одну сетку дня, у каждого 60 секунд, сравнение счёта асинхронно | средний | низкая | высокая: словари ru/en, проверка слов |
| 6 | **Truth or dare / Never have I ever** | Только мягкая версия как колода в «вопросах» | высокий в нише | низкая | контент; «острое» тянет рейтинг 17+, не берём |

## 4. Рекомендация

1. **Сначала «Нарисуй — угадай» (#2).** Самая дешёвая игра: почти всё уже построено. Она продолжает главный путь приложения («один рисует, другой видит») и даёт рисунки, которые остаются в комнате. Такого нет ни у одного прямого конкурента.
2. **Затем «Угадай, что ответит партнёр» (#1)** с режимом This or that. Это самый востребованный формат на рынке. Асинхронное раскрытие ответов решает проблему «партнёр не онлайн». Часть вопросов можно брать из вопроса дня, чтобы не плодить два банка контента.
3. **Кооп с Mochi (#3)** — когда будет презенс «оба в комнате». Это наш уникальный ход, но он работает, только если пара бывает онлайн одновременно; сначала стоит измерить, как часто это случается.
4. Классику (#4) и словесные (#5) отложить. Их хорошо делает GamePigeon, и пара уже играет в них в iMessage бесплатно. Если брать, то начать с Connect 4 с Mochi в роли соперника.
5. «Острые» игры не делать: рейтинг 17+ и тон не совпадают с уютной комнатой.

Общие правила для всех игр, по урокам конкурентов:
- Каждая игра пишет `GamePlayed` и влияет на Mochi, иначе получится «прикручено сбоку», как у Lovelee и Widgetable.
- Игра должна заканчиваться за 1–3 минуты. Отзывы Widgetable ругают игры за то, что они долгие и мало дают.
- Не закрывать игры за пейволлом на старте: у Paired, Pookie и Smush это главный источник жалоб в обзорах.

## Источники

- [Best Apps for Couples in 2026 — blushquest](https://blushquest.com/blog/best-apps-for-couples)
- [Top free couples apps in 2026 — luviduo](https://luviduo.com/free-couples-apps-compared/)
- [Best Couples Games (2026) — True Talk](https://truetalkapp.com/best-couples-games-apps/)
- [Couples Apps That Are Actually Free — Pookie](https://pookie-app.com/blog/couples-apps-that-are-actually-free/)
- [Best Couple Game Apps of 2026 — StayClose](https://stayclose.live/blog/best-couple-game-apps-2026/)
- [Widgetable: Besties & Couples — App Store](https://apps.apple.com/us/app/widgetable-besties-couples/id1641107226)
- [Paired: Couples & Relationship — App Store](https://apps.apple.com/app/id1469609343)
- [Couple Joy — screensdesign](https://screensdesign.com/apps/couple-joy-relationship-app/)
- [Foreplay Game — AlternativeTo](https://alternativeto.net/software/foreplay-game/about/)
- [Funny couples quizzes on TikTok — macmyths](https://macmyths.com/funny-couples-quizzes-on-tiktok-to-take-together/)
- [GamePigeon dominates students' screens — Chantilly News](https://chantillynews.org/8884/arts-and-style/game-pigeon-dominates-students-screens-once-again)
- [Top 5 GamePigeon games — Harbinger](https://arhsharbinger.com/43130/blogs/top-5-gamepigeon-games/)
- [Best games for long distance couples — Forge Press](https://forgepress.org/the-best-games-for-long-distance-couples-and-friends/)
- [Draw Something becomes most played game app — Everything PR](https://everything-pr.com/?p=33666)
- [What is Gartic Phone — Know Your Meme](https://knowyourmeme.com/editorials/guides/what-is-gartic-phone-and-why-do-streamers-love-it-the-multiplayer-drawing-game-explained)
- Внутреннее: [lovelee-features.md](lovelee-features.md), [competitor-landings.md](competitor-landings.md)

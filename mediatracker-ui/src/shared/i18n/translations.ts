export type Locale = "ru" | "en";

/**
 * Every user-facing string, both languages, on one line. Split across two files it was impossible
 * to see a translation pair without opening both, and adding a key meant remembering to edit two of
 * them — which is how they drifted apart.
 *
 * A leaf is a string or a function, and the pair keeps the same shape in both languages so
 * index.svelte.ts can resolve one and hand back the other.
 */
export const translations = {
  common: {
    add: { ru: "Добавить", en: "Add" },
    adding: { ru: "Добавление…", en: "Adding…" },
    save: { ru: "Сохранить", en: "Save" },
    delete: { ru: "Удалить", en: "Delete" },
    cancel: { ru: "Отмена", en: "Cancel" },
    retry: { ru: "Повторить", en: "Retry" },
    close: { ru: "Закрыть", en: "Close" },
    loading: { ru: "Загрузка…", en: "Loading…" },
    saving: { ru: "Сохранение…", en: "Saving…" },
    back: { ru: "Назад", en: "Back" },
    noData: { ru: "Пока нет данных", en: "No data yet" },
    comingSoon: { ru: "Скоро", en: "Coming soon" },
  },
  header: {
    description: {
      ru: "Личный трекер игр, фильмов, книг и сериалов",
      en: "Personal tracker for games, movies, books and TV shows",
    },
    searchButton: { ru: "Поиск тайтлов", en: "Search titles" },
    searchTooltip: {
      ru: "Поиск тайтлов — Ctrl+K",
      en: "Search titles — Ctrl+K",
    },
    addButton: { ru: "Добавить", en: "Add media" },
    language: { ru: "Язык интерфейса", en: "Interface language" },
  },
  navigation: {
    home: { ru: "Главная", en: "Home" },
    tvshow: { ru: "Сериалы", en: "TV Shows" },
    movie: { ru: "Фильмы", en: "Movies" },
    anime: { ru: "Аниме", en: "Anime" },
    manga: { ru: "Манга", en: "Manga" },
    game: { ru: "Игры", en: "Games" },
    book: { ru: "Книги", en: "Books" },
    create: { ru: "Добавить медиа", en: "Add media" },
    stats: { ru: "Статистика", en: "Statistics" },
    lists: { ru: "Списки", en: "Lists" },
    history: { ru: "История", en: "History" },
    calendar: { ru: "Календарь", en: "Calendar" },
    seasons: { ru: "Сезоны", en: "Seasons" },
    brand: { ru: "Медиа-трекер", en: "Media tracker" },
    toolsLabel: { ru: "Инструменты", en: "Tools" },
    settings: { ru: "Настройки", en: "Settings" },
    mainLabel: { ru: "Основная навигация", en: "Main navigation" },
  },
  library: {
    filtersLabel: { ru: "Фильтры библиотеки", en: "Library filters" },
    collectionLabel: { ru: "Медиатека", en: "Media library" },
    emptyTitle: { ru: "Ничего не найдено", en: "Nothing found" },
    emptyHint: {
      ru: "Попробуйте изменить фильтры или добавьте первый тайтл.",
      en: "Try another filter or add your first title.",
    },
    resultCount: {
      ru: (count: number) => `Всего: ${count}`,
      en: (count: number) => `Total: ${count}`,
    },
  },
  views: {
    homeTitle: { ru: "Моя медиатека", en: "My library" },
    inProgress: { ru: "В Процессе", en: "In progress" },
    upNext: { ru: "В Планах", en: "Up next" },
    recentlyCompleted: { ru: "Завершено", en: "Recently completed" },
    seasonsOf: {
      ru: (title: string) => `Сезоны: ${title}`,
      en: (title: string) => `Seasons: ${title}`,
    },
    historyTitle: { ru: "История активности", en: "Activity history" },
    historyHint: {
      ru: "Здесь отображаются даты начала и завершения из вашей медиатеки.",
      en: "This shows start and completion dates from your media library.",
    },
    calendarTitle: {
      ru: "Календарь релизов и обновлений",
      en: "Release & Update Calendar",
    },
    calendarSubtitle: {
      ru: "Расписание выхода серий, премьер и автоматических проверок новых глав",
      en: "Schedule of upcoming episodes, premieres and automatic chapter checks",
    },
    calendarFilterAll: { ru: "Все события", en: "All Events" },
    calendarFilterAllCategories: { ru: "Все категории", en: "All categories" },
    calendarFilterAllEvents: { ru: "Все события", en: "All events" },
    calendarFilterNoAutoRefresh: {
      ru: "Без автопроверок (только релизы и серии)",
      en: "Hide auto-checks (releases & episodes only)",
    },
    calendarFilterOnlyAutoRefresh: {
      ru: "Только автопроверки",
      en: "Auto-checks only",
    },
    calendarFilterOnlyAirDate: { ru: "Выход серий", en: "Episodes only" },
    calendarFilterOnlyRelease: { ru: "Премьеры и релизы", en: "Releases only" },
    calendarCategoryLabel: { ru: "Категория", en: "Category" },
    calendarEventKindLabel: { ru: "Тип события", en: "Event type" },
    calendarMoreEvents: {
      ru: (count: number) => `+${count} ещё`,
      en: (count: number) => `+${count} more`,
    },
    calendarFilterAutoRefresh: { ru: "Автопроверки", en: "Auto-checks" },
    calendarFilterAirDate: { ru: "Выход серий", en: "Episodes" },
    calendarFilterRelease: { ru: "Релизы", en: "Releases" },
    calendarViewMonth: { ru: "Сетка месяца", en: "Month View" },
    calendarViewFeed: { ru: "Лента ближайших", en: "Upcoming Feed" },
    calendarToday: { ru: "Сегодня", en: "Today" },
    calendarTomorrow: { ru: "Завтра", en: "Tomorrow" },
    calendarEmptyTitle: {
      ru: "В этом месяце нет запланированных событий",
      en: "No scheduled events this month",
    },
    calendarEmptyHint: {
      ru: "Здесь появятся даты автопроверок ваших онгоингов и расписание выхода серий",
      en: "Dates of automatic checks for your ongoing titles and episode schedules will appear here",
    },
    calendarCheckNow: { ru: "Проверить", en: "Check" },
    calendarChecking: { ru: "Проверка...", en: "Checking..." },
    calendarPrevMonth: { ru: "Предыдущий месяц", en: "Previous month" },
    calendarNextMonth: { ru: "Следующий месяц", en: "Next month" },
    calendarCurrentMonth: { ru: "Текущий месяц", en: "Current month" },
    calendarAllDays: { ru: "Все дни", en: "All days" },
    calendarReset: { ru: "Сбросить", en: "Reset" },
    calendarCellModePosters: { ru: "Обложки", en: "Covers" },
    calendarCellModeIcons: { ru: "Значки", en: "Icons" },
    calendarCheckUpdatesTooltip: {
      ru: "Проверить обновления",
      en: "Check for updates",
    },
    listsTitle: { ru: "Списки", en: "Lists" },
    listsHint: {
      ru: "Здесь появятся ваши собственные коллекции: собранные вручную подборки, сезоны, избранное и очереди на просмотр.",
      en: "Your own collections will live here: hand-picked watchlists, seasons, favorites and queues.",
    },
    listsCreate: { ru: "+ Создать список", en: "+ Create list" },
    listsCreateHint: {
      ru: "Пользовательские списки пока не реализованы — раздел готовится.",
      en: "Custom lists are not implemented yet — this section is being prepared.",
    },
    listsPresetWatchlist: { ru: "Очередь просмотра", en: "Watchlist" },
    listsPresetSeason: { ru: "Этот сезон", en: "This season" },
    listsPresetFavorites: { ru: "Избранное", en: "Favorites" },
    listsEmptyTitle: {
      ru: "Создайте свою первую коллекцию",
      en: "Create your first collection",
    },
    listsEmptyHint: {
      ru: "Собирайте тайтлы в тематические подборки и возвращайтесь к ним в любой момент.",
      en: "Gather titles into themed collections and come back to them any time.",
    },
    listCreate: { ru: "Создать список", en: "Create list" },
    listEdit: { ru: "Редактировать список", en: "Edit list" },
    listName: { ru: "Название", en: "Name" },
    listDescription: { ru: "Описание", en: "Description" },
    listColor: { ru: "Цвет", en: "Color" },
    listIcon: { ru: "Иконка", en: "Icon" },
    listModalHint: {
      ru: "Подберите название и стиль для вашей коллекции.",
      en: "Choose a name and style for your collection.",
    },
    listBack: { ru: "Назад к спискам", en: "Back to lists" },
    listTitles: {
      ru: (count: number) => {
        const mod10 = count % 10;
        const mod100 = count % 100;
        if (mod100 >= 11 && mod100 <= 19) return `${count} тайтлов`;
        if (mod10 === 1) return `${count} тайтл`;
        if (mod10 >= 2 && mod10 <= 4) return `${count} тайтла`;
        return `${count} тайтлов`;
      },
      en: (count: number) => `${count} ${count === 1 ? "title" : "titles"}`,
    },
    listUpdated: { ru: "Обновлён", en: "Updated" },
    listCreateFirst: {
      ru: "Создать первый список",
      en: "Create your first list",
    },
    listDelete: { ru: "Удалить список", en: "Delete list" },
    listConfirmDelete: {
      ru: (name: string) => `Удалить список «${name}»? Тайтлы останутся в медиатеке.`,
      en: (name: string) => `Delete “${name}”? Its titles will stay in your library.`,
    },
    listDeleted: { ru: "Список удалён", en: "List deleted" },
    listAdded: {
      ru: (name: string) => `Добавлено в список «${name}»`,
      en: (name: string) => `Added to “${name}”`,
    },
    listRemoved: {
      ru: (name: string) => `Удалено из списка «${name}»`,
      en: (name: string) => `Removed from “${name}”`,
    },
    listAddTo: { ru: "В списки", en: "Add to lists" },
    listPickerTitle: { ru: "Добавить в списки", en: "Add to lists" },
    listPickerEmpty: { ru: "Списков пока нет", en: "No lists yet" },
    listNew: { ru: "+ Новый список", en: "+ New list" },
    listRemoveItem: { ru: "Убрать из списка", en: "Remove from list" },
    listLoadError: {
      ru: "Не удалось загрузить списки",
      en: "Could not load lists",
    },
    listTypeManual: { ru: "Обычный список", en: "Manual list" },
    listTypeSmart: { ru: "Умный список", en: "Smart list" },
    smartBadge: { ru: "Умный", en: "Smart" },
    smartEditRules: { ru: "Изменить правила", en: "Edit rules" },
    smartPresets: { ru: "Быстрые пресеты", en: "Quick presets" },
    smartPresetMasterpieces: {
      ru: "Шедевры (9–10 ★)",
      en: "Masterpieces (9–10 ★)",
    },
    smartPresetMovieNight: {
      ru: "Фильмы на вечер (< 100 мин)",
      en: "Movie night (< 100 min)",
    },
    smartPresetShortAnime: {
      ru: "Короткое аниме (≤ 13 эп.)",
      en: "Short anime (≤ 13 ep.)",
    },
    smartPresetHighRated: {
      ru: "Высокий рейтинг в планах (≥ 8.0)",
      en: "Highly rated, planned (≥ 8.0)",
    },
    smartPresetShortBooks: {
      ru: "Быстрые книги (≤ 250 стр.)",
      en: "Quick reads (≤ 250 pages)",
    },
    smartCategories: { ru: "Типы медиа", en: "Media types" },
    smartCategoryGame: { ru: "Игры", en: "Games" },
    smartCategoryAnime: { ru: "Аниме", en: "Anime" },
    smartCategoryManga: { ru: "Манга", en: "Manga" },
    smartCategoryMovie: { ru: "Фильмы", en: "Movies" },
    smartCategoryTvShow: { ru: "Сериалы", en: "TV Shows" },
    smartCategoryBook: { ru: "Книги", en: "Books" },
    smartStatuses: { ru: "Статусы", en: "Statuses" },
    smartStatusPlanned: { ru: "В планах", en: "Planned" },
    smartStatusInProgress: { ru: "В процессе", en: "In progress" },
    smartStatusCompleted: { ru: "Завершено", en: "Completed" },
    smartStatusOnHold: { ru: "На паузе", en: "On hold" },
    smartStatusDropped: { ru: "Брошено", en: "Dropped" },
    smartMinScore: { ru: "Личная оценка от", en: "Min personal score" },
    smartMinExternalRating: {
      ru: "Внешний рейтинг от",
      en: "Min external rating",
    },
    smartOnlyUnrated: {
      ru: "Только без моей оценки",
      en: "Only unrated by me",
    },
    smartYearFrom: { ru: "Год от", en: "Year from" },
    smartYearTo: { ru: "Год до", en: "Year to" },
    smartMaxDuration: {
      ru: "Макс. минут (фильм/серия)",
      en: "Max duration (min)",
    },
    smartMaxDurationPlaceholder: { ru: "напр. 120", en: "e.g. 120" },
    smartMaxEpisodes: { ru: "Макс. серий", en: "Max episodes" },
    smartMaxEpisodesPlaceholder: { ru: "напр. 12", en: "e.g. 12" },
    smartMaxPages: { ru: "Макс. страниц", en: "Max pages" },
    smartMaxPagesPlaceholder: { ru: "напр. 300", en: "e.g. 300" },
    smartMaxChapters: { ru: "Макс. глав", en: "Max chapters" },
    smartMaxChaptersPlaceholder: { ru: "напр. 50", en: "e.g. 50" },
    smartCreator: {
      ru: "Студия, режиссёр или автор",
      en: "Studio, director or author",
    },
    smartCreatorPlaceholder: { ru: "напр. Ghibli", en: "e.g. Ghibli" },
    smartSortBy: { ru: "Сортировка", en: "Sort by" },
    smartSortScore: { ru: "По оценке", en: "By score" },
    smartSortExternalRating: { ru: "По рейтингу баз", en: "By ext. rating" },
    smartSortReleaseYear: { ru: "По году", en: "By year" },
    smartSortCreatedAt: { ru: "По дате добавления", en: "By date added" },
    smartSortTitle: { ru: "По алфавиту", en: "Alphabetically" },
    smartSortOrder: { ru: "Направление", en: "Order" },
    smartSortDesc: { ru: "По убыванию", en: "Descending" },
    smartSortAsc: { ru: "По возрастанию", en: "Ascending" },
    smartLimit: { ru: "Лимит", en: "Limit" },
    smartLimitPlaceholder: { ru: "напр. 50", en: "e.g. 50" },
    smartPreviewCount: {
      ru: (n: number) => {
        const mod10 = n % 10;
        const mod100 = n % 100;
        const word =
          mod100 >= 11 && mod100 <= 19
            ? "тайтлов"
            : mod10 === 1
              ? "тайтл"
              : mod10 >= 2 && mod10 <= 4
                ? "тайтла"
                : "тайтлов";
        return `Сейчас подходит: ${n} ${word}`;
      },
      en: (n: number) => `Currently matching: ${n} title${n === 1 ? "" : "s"}`,
    },
    noSeasons: {
      ru: "У этого сериала пока нет сезонов.",
      en: "This TV show has no seasons yet.",
    },
    groupByType: { ru: "Группировать по типу", en: "Group by type" },
    clearHistory: { ru: "Очистить историю", en: "Clear history" },
    confirmClearHistory: {
      ru: "Вы уверены, что хотите полностью очистить историю?",
      en: "Are you sure you want to clear all history?",
    },
    confirmDeleteHistoryEntry: {
      ru: "Удалить эту запись из истории?",
      en: "Delete this history entry?",
    },
    historyCleared: { ru: "История очищена", en: "History cleared" },
    historyEntryDeleted: {
      ru: "Запись удалена из истории",
      en: "History entry deleted",
    },
    filterByDate: { ru: "Фильтр по дате", en: "Filter by date" },
    allDays: { ru: "Все дни", en: "All days" },
    resetDate: { ru: "Сбросить дату", en: "Reset date" },
    noActivityForDate: {
      ru: "Нет записей активности за выбранный день",
      en: "No activity records for the selected day",
    },
    noActivity: { ru: "Нет записей активности", en: "No activity records" },
    tabChronicle: { ru: "Хроника", en: "Chronicle" },
    tabActivity: { ru: "Активность", en: "Activity" },
    scaleMonths: { ru: "По месяцам", en: "By month" },
    scaleYears: { ru: "По годам", en: "By year" },
    includeInProgress: { ru: "Включая начатые", en: "Include in-progress" },
    yearSummaryCount: {
      ru: (count: number) => {
        const mod10 = count % 10;
        const mod100 = count % 100;
        if (mod100 >= 11 && mod100 <= 19) return `${count} тайтлов`;
        if (mod10 === 1) return `${count} тайтл`;
        if (mod10 >= 2 && mod10 <= 4) return `${count} тайтла`;
        return `${count} тайтлов`;
      },
      en: (count: number) => `${count} ${count === 1 ? "title" : "titles"}`,
    },
    yearAvgScore: {
      ru: (score: string) => `★ ${score}`,
      en: (score: string) => `★ ${score}`,
    },
    yearFavorite: {
      ru: (title: string) => `Топ года: ${title}`,
      en: (title: string) => `Top of the year: ${title}`,
    },
    undatedCompletedTitle: {
      ru: (count: number) => `Завершено без точной даты (${count})`,
      en: (count: number) => `Completed without a date (${count})`,
    },
    emptyChronicleTitle: { ru: "Хроника пуста", en: "Chronicle is empty" },
    emptyChronicleHint: {
      ru: "Отметьте тайтлы как завершённые — они появятся здесь по годам.",
      en: "Mark titles as completed — they will appear here by year.",
    },
    titleAdded: { ru: "Тайтл добавлен", en: "Title added" },
    titleDeleted: { ru: "Тайтл удалён", en: "Title deleted" },
    statusPrefix: { ru: "Статус:", en: "Status:" },
    progressPrefix: { ru: "Прогресс:", en: "Progress:" },
    readPrefix: { ru: "Прочитано:", en: "Read:" },
    scorePrefix: { ru: "Оценка:", en: "Score:" },
    achievementPrefix: { ru: "Достижение:", en: "Achievement:" },
  },
  types: {
    game: { ru: "Игра", en: "Game" },
    movie: { ru: "Фильм", en: "Movie" },
    tvshow: { ru: "Сериал", en: "TV Show" },
    book: { ru: "Книга", en: "Book" },
    manga: { ru: "Манга", en: "Manga" },
  },
  status: {
    label: { ru: "Статус", en: "Status" },
    all: { ru: "Все", en: "All" },
    planned: { ru: "В планах", en: "Planned" },
    inProgress: { ru: "В процессе", en: "In progress" },
    completed: { ru: "Завершено", en: "Completed" },
    paused: { ru: "На паузе", en: "On hold" },
    dropped: { ru: "Брошено", en: "Dropped" },
  },
  creator: {
    director: { ru: "Режиссёр", en: "Director" },
    author: { ru: "Автор", en: "Author" },
    studio: { ru: "Студия", en: "Studio" },
    network: { ru: "Телесеть", en: "Network" },
    mangaka: { ru: "Мангака", en: "Mangaka" },
    developer: { ru: "Разработчик", en: "Developer" },
    inLibrary: { ru: "В вашей медиатеке", en: "In your library" },
    titlesCount: {
      ru: (count: number) => {
        const lastTwo = count % 100;
        const last = count % 10;
        const word =
          lastTwo >= 11 && lastTwo <= 14
            ? "тайтлов"
            : last === 1
              ? "тайтл"
              : last >= 2 && last <= 4
                ? "тайтла"
                : "тайтлов";
        return `${count} ${word}`;
      },
      en: (count: number) => `${count} ${count === 1 ? "title" : "titles"}`,
    },
    completedOf: {
      ru: (completed: number, total: number) => `Завершено: ${completed} из ${total}`,
      en: (completed: number, total: number) => `Completed: ${completed} of ${total}`,
    },
    averageScore: { ru: "Средний балл", en: "Average score" },
    otherWorks: {
      ru: "Другие работы в вашей медиатеке",
      en: "Other works in your library",
    },
    noOtherItems: {
      ru: "Это единственное произведение автора в вашей медиатеке",
      en: "This is the only work by this creator in your library",
    },
    searchMore: { ru: "Искать ещё работы", en: "Search for more works" },
    loading: { ru: "Загружаем статистику…", en: "Loading creator stats…" },
    noCreator: {
      ru: "Информация о создателе пока недоступна",
      en: "Creator information is not available yet",
    },
    staffHeading: { ru: "Авторы и создатели", en: "Staff" },
  },
  sort: {
    label: { ru: "Сортировка", en: "Sort" },
    newest: { ru: "Сначала новые", en: "Newest first" },
    oldest: { ru: "Сначала старые", en: "Oldest first" },
    rating: { ru: "По рейтингу", en: "Top rated" },
    title: { ru: "По алфавиту", en: "Alphabetical" },
  },
  grouping: {
    label: { ru: "Группировка", en: "Grouping" },
    byStatus: { ru: "По статусу", en: "By status" },
    byFranchise: { ru: "По франшизе", en: "By franchise" },
    all: { ru: "Все", en: "All" },
    noFranchise: { ru: "Без франшизы", en: "No franchise" },
  },
  stats: {
    title: { ru: "Статистика", en: "Statistics" },
    totalItems: { ru: "Тайтлов в библиотеке", en: "Titles in library" },
    completedItems: { ru: "Завершено", en: "Completed" },
    inProgressItems: { ru: "В процессе", en: "In progress" },
    plannedItems: { ru: "Запланировано", en: "Planned" },
    hours: { ru: "Часов в играх", en: "Hours played" },
    pages: { ru: "Страниц прочитано", en: "Pages read" },
    chapters: { ru: "Глав прочитано", en: "Chapters read" },
    episodes: { ru: "Серий просмотрено", en: "Episodes watched" },
    gamesCompleted: { ru: "Пройдено игр", en: "Games completed" },
    booksCompleted: { ru: "Прочитано книг", en: "Books read" },
    moviesCompleted: { ru: "Просмотрено фильмов", en: "Movies watched" },
    heroTitle: {
      ru: (hours: string, titles: string) => `Вы провели ${hours} ч. за ${titles} тайтлами.`,
      en: (hours: string, titles: string) => `You spent ${hours} hours across ${titles} titles.`,
    },
    heroSubtitle: {
      ru: (days: string) => `Это ${days} дн. непрерывных историй, миров и приключений.`,
      en: (days: string) => `${days} days of stories, worlds, and adventures.`,
    },
    activityStreak: { ru: "Стрик активности", en: "Activity streak" },
    streakDays: {
      ru: (count: number) => `${count} дн. активности подряд`,
      en: (count: number) => `${count} active days in a row`,
    },
    averageScore: { ru: "Средний балл", en: "Average rating" },
    completed: { ru: "Завершено", en: "Completed" },
    hoursShort: { ru: "ч.", en: "h" },
    totalTime: { ru: "Всего времени", en: "Total time" },
    games: { ru: "Игры", en: "Games" },
    movies: { ru: "Фильмы", en: "Movies" },
    series: { ru: "Сериалы", en: "TV shows" },
    anime: { ru: "Аниме", en: "Anime" },
    manga: { ru: "Манга", en: "Manga" },
    books: { ru: "Книги", en: "Books" },
    episodesShort: { ru: "эп.", en: "ep." },
    pagesShort: { ru: "стр.", en: "pp." },
    chaptersShort: { ru: "гл.", en: "ch." },
    ratingPsychology: { ru: "Психология оценок", en: "Rating breakdown" },
    averagePrefix: { ru: "Средняя", en: "Average" },
    ratingDistribution: {
      ru: "Распределение оценок",
      en: "Rating distribution",
    },
    averageByCategory: {
      ru: "Средний балл по категориям",
      en: "Average rating by category",
    },
    monthlyActivity: {
      ru: "Активность за 12 месяцев",
      en: "Activity over 12 months",
    },
    completedInYear: {
      ru: (count: number) => `${count} за год`,
      en: (count: number) => `${count} this year`,
    },
    completedTooltip: {
      ru: (count: number) => `${count} завершено`,
      en: (count: number) => `${count} completed`,
    },
    months: {
      jan: { ru: "Янв", en: "Jan" },
      feb: { ru: "Фев", en: "Feb" },
      mar: { ru: "Мар", en: "Mar" },
      apr: { ru: "Апр", en: "Apr" },
      may: { ru: "Май", en: "May" },
      jun: { ru: "Июн", en: "Jun" },
      jul: { ru: "Июл", en: "Jul" },
      aug: { ru: "Авг", en: "Aug" },
      sep: { ru: "Сен", en: "Sep" },
      oct: { ru: "Окт", en: "Oct" },
      nov: { ru: "Ноя", en: "Nov" },
      dec: { ru: "Дек", en: "Dec" },
    },
    topGenres: { ru: "Любимые жанры", en: "Top genres" },
    genreCategories: {
      all: { ru: "Все", en: "All" },
      game: { ru: "Игры", en: "Games" },
      movie: { ru: "Фильмы", en: "Movies" },
      series: { ru: "Сериалы", en: "TV shows" },
      anime: { ru: "Аниме", en: "Anime" },
      manga: { ru: "Манга", en: "Manga" },
      book: { ru: "Книги", en: "Books" },
    },
    genres: {
      action: { ru: "Боевик", en: "Action" },
      adventure: { ru: "Приключения", en: "Adventure" },
      comedy: { ru: "Комедия", en: "Comedy" },
      drama: { ru: "Драма", en: "Drama" },
      sciFi: { ru: "Фантастика", en: "Sci-Fi" },
      fantasy: { ru: "Фэнтези", en: "Fantasy" },
      romance: { ru: "Романтика", en: "Romance" },
      thriller: { ru: "Триллер", en: "Thriller" },
      horror: { ru: "Ужасы", en: "Horror" },
      mystery: { ru: "Детектив", en: "Mystery" },
      sliceOfLife: { ru: "Повседневность", en: "Slice of Life" },
      supernatural: { ru: "Сверхъестественное", en: "Supernatural" },
      psychological: { ru: "Психологическое", en: "Psychological" },
      philosophical: { ru: "Философия", en: "Philosophical" },
      historical: { ru: "Исторический", en: "Historical" },
      crime: { ru: "Криминал", en: "Crime" },
      war: { ru: "Военный", en: "War" },
      western: { ru: "Вестерн", en: "Western" },
      animation: { ru: "Анимация", en: "Animation" },
      documentary: { ru: "Документальный", en: "Documentary" },
      family: { ru: "Семейный", en: "Family" },
      sports: { ru: "Спорт", en: "Sports" },
      music: { ru: "Музыка", en: "Music" },
      biography: { ru: "Биография", en: "Biography" },
      filmNoir: { ru: "Фильм-нуар", en: "Film Noir" },
      cyberpunk: { ru: "Киберпанк", en: "Cyberpunk" },
      steampunk: { ru: "Стимпанк", en: "Steampunk" },
      postApocalyptic: { ru: "Постапокалипсис", en: "Post-Apocalyptic" },
      survival: { ru: "Выживание", en: "Survival" },
      superhero: { ru: "Супергерои", en: "Superhero" },
      mecha: { ru: "Меха", en: "Mecha" },
      mahouShoujo: { ru: "Махо-сёдзё", en: "Mahou Shoujo" },
      isekai: { ru: "Исекай", en: "Isekai" },
      martialarts: { ru: "Боевые искусства", en: "Martial Arts" },
      school: { ru: "Школа", en: "School" },
      workLife: { ru: "Офисная жизнь", en: "Work Life" },
      gourmet: { ru: "Гурман", en: "Gourmet" },
      medical: { ru: "Медицина", en: "Medical" },
      political: { ru: "Политика", en: "Political" },
      space: { ru: "Космос", en: "Space" },
      vampire: { ru: "Вампиры", en: "Vampire" },
      demons: { ru: "Демоны", en: "Demons" },
      zombies: { ru: "Зомби", en: "Zombies" },
      animals: { ru: "Животные", en: "Animals" },
      harem: { ru: "Гарем", en: "Harem" },
      ecchi: { ru: "Этти", en: "Ecchi" },
      erotica: { ru: "Эротика", en: "Erotica" },
      hentai: { ru: "Хентай", en: "Hentai" },
      gore: { ru: "Жестокость", en: "Gore" },
      boysLove: { ru: "Яой", en: "Boys' Love" },
      girlsLove: { ru: "Юри", en: "Girls' Love" },
      genderBender: { ru: "Смена пола", en: "Gender Bender" },
      shounen: { ru: "Сёнэн", en: "Shounen" },
      seinen: { ru: "Сэйнэн", en: "Seinen" },
      shoujo: { ru: "Сёдзё", en: "Shoujo" },
      josei: { ru: "Дзёсэй", en: "Josei" },
      doujinshi: { ru: "Додзинси", en: "Doujinshi" },
      webComic: { ru: "Веб-комикс", en: "Web Comic" },
      realityTv: { ru: "Реалити-шоу", en: "Reality TV" },
      gameShow: { ru: "Игровое шоу", en: "Game Show" },
      talkShow: { ru: "Ток-шоу", en: "Talk Show" },
      news: { ru: "Новости", en: "News" },
      short: { ru: "Короткометражка", en: "Short" },
      tvMovie: { ru: "Телевизионный фильм", en: "TV Movie" },
      rpg: { ru: "RPG", en: "RPG" },
      shooter: { ru: "Шутер", en: "Shooter" },
      strategy: { ru: "Стратегия", en: "Strategy" },
      simulation: { ru: "Симулятор", en: "Simulation" },
      puzzle: { ru: "Головоломка", en: "Puzzle" },
      platformer: { ru: "Платформер", en: "Platformer" },
      fighting: { ru: "Файтинг", en: "Fighting" },
      racing: { ru: "Гонки", en: "Racing" },
      arcade: { ru: "Аркада", en: "Arcade" },
      indie: { ru: "Инди", en: "Indie" },
      casual: { ru: "Казуальные", en: "Casual" },
      mmo: { ru: "MMO", en: "MMO" },
      boardAndCard: { ru: "Настольные и карточные", en: "Board & Card" },
      freeToPlay: { ru: "Бесплатные", en: "Free to Play" },
      earlyAccess: { ru: "Ранний доступ", en: "Early Access" },
      utilitiesAndSoftware: { ru: "Утилиты", en: "Utilities & Software" },
      poetry: { ru: "Поэзия", en: "Poetry" },
      artAndDesign: { ru: "Искусство и дизайн", en: "Art & Design" },
      science: { ru: "Наука", en: "Science" },
      programmingAndIt: { ru: "Программирование и IT", en: "Programming & IT" },
      businessAndEconomics: {
        ru: "Бизнес и экономика",
        en: "Business & Economics",
      },
      education: { ru: "Образование", en: "Education" },
      selfHelp: { ru: "Самопомощь", en: "Self-Help" },
      religion: { ru: "Религия", en: "Religion" },
      // Legacy canonical names that can still sit in old tracker.db rows
      reality: { ru: "Реалити", en: "Reality" },
      kids: { ru: "Детский", en: "Kids" },
    },
    backlogTitle: {
      ru: "Баланс медиатеки (Индекс Цундоку)",
      en: "Library balance (Tsundoku Index)",
    },
    emptyVerdict: {
      ru: "Ваша медиатека пока пуста. Добавьте свои первые произведения!",
      en: "Your library is empty. Add your first titles!",
    },
    productiveVerdict: {
      ru: "🟢 Высокая продуктивность! Вы завершаете больше половины того, что начинаете. Бэклог под полным контролем.",
      en: "🟢 Highly productive! You finish more than half of what you start. Your backlog is under control.",
    },
    balancedVerdict: {
      ru: "🟡 Здоровый культурный баланс. Коллекция планомерно пополняется и осваивается.",
      en: "🟡 A healthy cultural balance. Your collection keeps growing and getting explored.",
    },
    tsundokuVerdict: {
      ru: "📚 Истинный дух Цундоку! Стопка запланированного внушительна — библиотека полна будущих открытий. Самое время выбрать тайтл на вечер.",
      en: "📚 The spirit of Tsundoku! Your planned stack is full of future discoveries. Pick a title for tonight.",
    },
    inProgress: { ru: "В процессе", en: "In progress" },
    planned: { ru: "В планах", en: "Planned" },
    segmentTooltip: {
      ru: (label: string, count: number, percent: number) => `${label}: ${count} (${percent}%)`,
      en: (label: string, count: number, percent: number) => `${label}: ${count} (${percent}%)`,
    },
    achievements: { ru: "Достижения медиатеки", en: "Library achievements" },
    unlockedCount: {
      ru: (count: number, percent: number) => `${count} из 6 разблокировано (${percent}%)`,
      en: (count: number, percent: number) => `${count} of 6 unlocked (${percent}%)`,
    },
    unlocked: { ru: "РАЗБЛОКИРОВАНО ✓", en: "UNLOCKED ✓" },
    progress: { ru: "Прогресс", en: "Progress" },
    badges: {
      hundredClub: {
        title: { ru: "Клуб сотен", en: "Century Club" },
        description: {
          ru: "Завершить 100 произведений",
          en: "Complete 100 titles",
        },
      },
      bibliophile: {
        title: { ru: "Библиофил", en: "Bibliophile" },
        description: {
          ru: "Прочитать 1,000+ страниц или глав",
          en: "Read 1,000+ pages or chapters",
        },
      },
      streakMaster: {
        title: { ru: "Мастер стриков", en: "Streak Master" },
        description: {
          ru: "Удержать стрик активности от 7 дней",
          en: "Maintain an activity streak of 7 days",
        },
      },
      timeKeeper: {
        title: { ru: "Хранитель времени", en: "Time Keeper" },
        description: {
          ru: "Провести суммарно 100+ часов за медиа",
          en: "Spend 100+ hours with media",
        },
      },
      perfectionist: {
        title: { ru: "Перфекционист", en: "Perfectionist" },
        description: {
          ru: "Поставить 10 звезд хотя бы 3 тайтлам",
          en: "Give a 10-star rating to at least 3 titles",
        },
      },
      omnivore: {
        title: { ru: "Культурный омнивор", en: "Cultural Omnivore" },
        description: {
          ru: "Активность хотя бы в 4 форматах медиа",
          en: "Be active in at least 4 media formats",
        },
      },
    },
    heatmapTitle: {
      ru: "Активность за год",
      en: "Activity over the past year",
    },
    heatmapTotal: {
      ru: (count: number) => `${count} действий за год`,
      en: (count: number) => `${count} actions this year`,
    },
    heatmapTooltip: {
      ru: (date: string, count: number) => `${date}: ${count} действий`,
      en: (date: string, count: number) => `${date}: ${count} actions`,
    },
    less: { ru: "Меньше", en: "Less" },
    more: { ru: "Больше", en: "More" },
    tabSummary: { ru: "Сводка", en: "Summary" },
    tabTaste: { ru: "Профиль вкуса", en: "Taste profile" },
    scopeCompleted: { ru: "✓ Только завершённые", en: "Completed only" },
    scopeAll: { ru: "⚡ Все с прогрессом", en: "All with progress" },
    taste: {
      personaBadge: { ru: "Архетип вкуса", en: "Taste archetype" },
      personas: {
        critic: {
          title: { ru: "Строгий критик", en: "Strict Critic" },
          description: {
            ru: "Вы держите свою медиатеку на самых высоких стандартах: немногим удается вас впечатлить, и даже признанные шедевры получают скептический прищур. Ваша библиотека — это зал суда, где проходной балл нужно заслужить кровью и потом.",
            en: "You hold your library to sky-high standards: few titles manage to impress you, and even acclaimed masterpieces earn a skeptical squint. Your collection is a courtroom where passing marks must be hard-won.",
          },
          traits: {
            ru: ["Высокие стандарты", "Честные оценки", "Неподкупный вкус"],
            en: ["High standards", "Honest reviews", "Uncompromising taste"],
          },
        },
        enthusiast: {
          title: { ru: "Щедрый вдохновитель", en: "Generous Enthusiast" },
          description: {
            ru: "Вы умеете искренне влюбляться в произведения и щедро одариваете авторов девятками и десятками. Для вас искусство — это источник восторга и сопереживания, а не повод для препарирования чужих ошибок.",
            en: "You fall in love with stories whole-heartedly and hand out top scores with infectious joy. For you, media is a wellspring of empathy and delight rather than an exercise in finding flaws.",
          },
          traits: {
            ru: ["Искренний восторг", "Высокие оценки", "Открытое сердце"],
            en: ["Pure enthusiasm", "Generous marks", "Open heart"],
          },
        },
        perfectionist: {
          title: {
            ru: "Перфекционист-завершитель",
            en: "Perfectionist Completer",
          },
          description: {
            ru: "Вы не оставляете историю на середине: начав — доводите до финала. Бросить тайтл для вас почти недопустимая капитуляция, а заполненные шкалы прогресса — памятник железной дисциплине.",
            en: "You never leave a story half-told: once started, you see it through. Dropping a title feels unthinkable, and your completed progress bars stand as a monument to iron discipline.",
          },
          traits: {
            ru: ["Доводит до конца", "Не бросает начатое", "Железный фокус"],
            en: ["Finisher", "Never DNFs", "Iron focus"],
          },
        },
        tsundoku_master: {
          title: { ru: "Хранитель Цундоку", en: "Tsundoku Master" },
          description: {
            ru: "Азарт собирательства опережает скорость потребления: ваш вишлист и бэклог превратились в сокровищницу бесконечных возможностей. Вы коллекционируете потенциальные миры быстрее, чем успеваете их исследовать.",
            en: "The thrill of discovery outpaces the clock: your backlog is a grand treasury of endless possibilities. You collect promised adventures faster than reality allows you to experience them.",
          },
          traits: {
            ru: ["Бесконечный бэклог", "Охотник за сокровищами", "Мечтатель"],
            en: ["Infinite backlog", "Treasure hunter", "Dreamer"],
          },
        },
        manga_reader: {
          title: { ru: "Исследователь манги", en: "Manga Digger" },
          description: {
            ru: "Черно-белые фреймы, сканлейт и ритм раскадровки — ваша главная стихия. Вы поглощаете сотни глав залпом, читаете справа налево на автомате и живете в предвкушении еженедельных клиффхэнгеров.",
            en: "Ink, panels, and dynamic pacing define your media life. You devour hundreds of chapters in a single sitting, effortlessly scan right-to-left, and thrive on weekly cliffhangers.",
          },
          traits: {
            ru: ["Охотник за главами", "Знаток манхвы", "Визуальный темп"],
            en: ["Chapter hunter", "Manhwa connoisseur", "Visual pacing"],
          },
        },
        otaku: {
          title: { ru: "Аниме-синефил", en: "Anime Cinephile" },
          description: {
            ru: "Аниме забирает ключевые часы вашего отдыха: вы ориентируетесь в студиях, различаете почерк аниматоров сакуги и узнаете любимых сэйю с первой реплики. Ваша карта вкуса нарисована культовыми опенингами и сезонными онгоингами.",
            en: "Anime claims the crown in your free time: you track visionary directors, celebrate sakuga animation, and recognize favorite voice actors instantly. Your world is mapped by iconic openings and seasonal premieres.",
          },
          traits: {
            ru: ["Фокус на аниме", "Знаток студий", "Сакуга-эстет"],
            en: ["Anime focus", "Studio connoisseur", "Sakuga lover"],
          },
        },
        gamer: {
          title: { ru: "Хардкорный геймер", en: "Hardcore Gamer" },
          description: {
            ru: "Интерактивный опыт для вас превыше пассивного созерцания. Вы погружаетесь в механики, оттачиваете скилл и проводите десятки часов в комплексных виртуальных вселенных, проверяя мир на прочность.",
            en: "Interactive experiences trump passive watching every time. You dive into deep gameplay loops, master complex systems, and spend dozens of hours exploring virtual worlds.",
          },
          traits: {
            ru: ["Глубокое погружение", "Мастер механик", "Интерактивность"],
            en: ["Deep immersion", "Mechanics master", "Interactive focus"],
          },
        },
        bookworm: {
          title: { ru: "Литературный эстет", en: "Literary Bookworm" },
          description: {
            ru: "Вы цените силу печатного слова, глубокие монологи и неспешное развитие авторской мысли. В мире быстрого медиа вы остаетесь верны шелесту страниц, экранам ридеров и силе воображения.",
            en: "You revere the written word, deep character monologues, and narrative depth. Amidst rapid-fire media, you stay true to the quiet majesty of great literature.",
          },
          traits: {
            ru: ["Сила слова", "Вдумчивое чтение", "Богатое воображение"],
            en: ["Power of prose", "Mindful reading", "Rich imagination"],
          },
        },
        cinephile: {
          title: { ru: "Киноман-эстет", en: "Cinephile Connoisseur" },
          description: {
            ru: "Кинематограф для вас — высшая форма драматического искусства. Вы чутки к композиции кадра, режиссерскому видению и актерской игре, отдавая предпочтение законченным полуторачасовым высказываниям.",
            en: "Cinema is the purest stage for your dramatic sensibilities. You appreciate framing, lighting, and directorial vision delivered within a focused feature film.",
          },
          traits: {
            ru: ["Визуальный язык", "Авторское кино", "Режиссерский почерк"],
            en: ["Visual language", "Auteur cinema", "Directorial style"],
          },
        },
        serial_binger: {
          title: { ru: "Сериальный марафонец", en: "Serial Binger" },
          description: {
            ru: "Вы любите масштабные арки персонажей, которые раскрываются на протяжении нескольких сезонов. Кнопка «Следующая серия» нажимается сама собой, а выходные легко растворяются в захватывающих теледрамах.",
            en: "You love sprawling narrative arcs that unfold across multiple seasons. The 'Next Episode' prompt is an irresistible reflex, and whole weekends happily vanish into compelling serialized television.",
          },
          traits: {
            ru: ["Запоем по сезонам", "Сюжетные арки", "Телеман"],
            en: ["Season binger", "Complex plotlines", "Serial enthusiast"],
          },
        },
        dark_philosopher: {
          title: { ru: "Сэйнэн-мыслитель", en: "Seinen Philosopher" },
          description: {
            ru: "Вас манят мрачные сюжеты, психологическое напряжение, неоднозначные антигерои и экзистенциальные дилеммы. Вы ищете в историях не легкое утешение, а честный разговор о человеческой природе.",
            en: "You gravitate toward psychological tension, morally grey antiheroes, existential quandaries, and dark suspense, exploring the shadows of the human condition.",
          },
          traits: {
            ru: ["Мрачный реализм", "Психологизм", "Философский подтекст"],
            en: ["Grim realism", "Psychological depth", "Philosophical nuance"],
          },
        },
        cozy_hedonist: {
          title: { ru: "Уютный гедонист", en: "Cozy Hedonist" },
          description: {
            ru: "Повседневность, мягкий юмор и романтика — ваше идеальное убежище после шумного дня. Вы цените душевное тепло, неторопливый темп и комфортную атмосферу, возвращающую веру в добро.",
            en: "Slice of life, warm humor, and gentle romance are your sanctuary. You cherish comforting atmospheres, unhurried pacing, and heartfelt stories that restore your peace of mind.",
          },
          traits: {
            ru: ["Уютная атмосфера", "Доброта историй", "Антистресс"],
            en: ["Cozy vibes", "Warmhearted tales", "Stress-free comfort"],
          },
        },
        action_junkie: {
          title: { ru: "Адреналиновый искатель", en: "Action Junkie" },
          description: {
            ru: "Вы живете ради захватывающего экшена, головокружительного драйва и кульминационных битв. Чем выше ставки, динамичнее монтаж и острее интрига — тем сильнее бьется ваше сердце.",
            en: "You live for breathtaking spectacles, pulsing adrenaline, and climactic showdowns where stakes and tempo are pushed to the limit.",
          },
          traits: {
            ru: ["Высокий темп", "Драйв и зрелищность", "Боевой дух"],
            en: ["High tempo", "Kinetic spectacle", "Fighting spirit"],
          },
        },
        visionary: {
          title: { ru: "Футурист-визионер", en: "Futurist Visionary" },
          description: {
            ru: "Фантастика и киберпанк лидируют в вашей коллекции: вас тянет в миры, где мегакорпорации, звездные корабли и слабости человеческой природы сталкиваются лбами. Ваш любимый вопрос — «а что будет дальше?».",
            en: 'Science fiction and cyberpunk lead your collection: you gravitate to worlds where megacorporations, starships and human weakness collide. Your favorite question is "and what happens next?".',
          },
          traits: {
            ru: ["Жанры будущего", "Технологии и космос", "Широкий горизонт"],
            en: ["Future genres", "Tech and space", "Expansive horizons"],
          },
        },
        omnivore: {
          title: { ru: "Культурный омнивор", en: "Cultural Omnivore" },
          description: {
            ru: "Вы пробуете все, что предлагает индустрия: игры, кино, сериалы, книги и манга делят ваше время в гармоничном балансе. Ни один формат не держит монополию, и ваши культурные горизонты по-настоящему безграничны.",
            en: "You taste everything the culture industry serves: games, cinema, series, books, and manga share your time in harmonic balance. No single medium holds a monopoly, giving you truly expansive cultural horizons.",
          },
          traits: {
            ru: ["Все форматы", "Без жанровых рамок", "Энциклопедичность"],
            en: ["All formats", "No genre limits", "Eclectic appetite"],
          },
        },
        archivist: {
          title: { ru: "Вдумчивый архивариус", en: "Thoughtful Archivist" },
          description: {
            ru: "Вы движетесь в своем темпе: медленнее, глубже, без погони за хайпом. Библиотека растет капля за каплей — значит, каждый тайтл в ней выбран осознанно и бережно сохранен.",
            en: "You move at your own pace: slower, deeper, without chasing trends. Your library grows drop by drop, meaning every title was chosen mindfully and preserved with care.",
          },
          traits: {
            ru: ["Спокойный темп", "Глубина, а не скорость", "Осознанный выбор"],
            en: ["Mindful pace", "Depth over speed", "Intentional curation"],
          },
        },
      },
      traits: {
        high_standards: { ru: "Высокие стандарты", en: "High standards" },
        honest_reviews: { ru: "Честные оценки", en: "Honest reviews" },
        uncompromising_taste: { ru: "Неподкупный вкус", en: "Uncompromising taste" },
        pure_enthusiasm: { ru: "Искренний восторг", en: "Pure enthusiasm" },
        generous_marks: { ru: "Высокие оценки", en: "Generous marks" },
        open_heart: { ru: "Открытое сердце", en: "Open heart" },
        finisher: { ru: "Доводит до конца", en: "Finisher" },
        no_dnf: { ru: "Не бросает начатое", en: "Never DNFs" },
        iron_focus: { ru: "Железный фокус", en: "Iron focus" },
        infinite_backlog: { ru: "Бесконечный бэклог", en: "Infinite backlog" },
        treasure_hunter: { ru: "Охотник за сокровищами", en: "Treasure hunter" },
        dreamer: { ru: "Мечтатель", en: "Dreamer" },
        chapter_hunter: { ru: "Охотник за главами", en: "Chapter hunter" },
        manhwa_connoisseur: { ru: "Знаток манхвы", en: "Manhwa connoisseur" },
        visual_pacing: { ru: "Визуальный темп", en: "Visual pacing" },
        anime_focus: { ru: "Фокус на аниме", en: "Anime focus" },
        studio_connoisseur: { ru: "Знаток студий", en: "Studio connoisseur" },
        sakuga_lover: { ru: "Сакуга-эстет", en: "Sakuga lover" },
        deep_immersion: { ru: "Глубокое погружение", en: "Deep immersion" },
        mechanics_master: { ru: "Мастер механик", en: "Mechanics master" },
        interactive_focus: { ru: "Интерактивность", en: "Interactive focus" },
        power_of_prose: { ru: "Сила слова", en: "Power of prose" },
        mindful_reading: { ru: "Вдумчивое чтение", en: "Mindful reading" },
        rich_imagination: { ru: "Богатое воображение", en: "Rich imagination" },
        visual_language: { ru: "Визуальный язык", en: "Visual language" },
        auteur_cinema: { ru: "Авторское кино", en: "Auteur cinema" },
        directorial_style: { ru: "Режиссерский почерк", en: "Directorial style" },
        season_binger: { ru: "Запоем по сезонам", en: "Season binger" },
        complex_plotlines: { ru: "Сюжетные арки", en: "Complex plotlines" },
        serial_enthusiast: { ru: "Телеман", en: "Serial enthusiast" },
        grim_realism: { ru: "Мрачный реализм", en: "Grim realism" },
        psychological_depth: { ru: "Психологизм", en: "Psychological depth" },
        philosophical_nuance: { ru: "Философский подтекст", en: "Philosophical nuance" },
        cozy_vibes: { ru: "Уютная атмосфера", en: "Cozy vibes" },
        warmhearted_tales: { ru: "Доброта историй", en: "Warmhearted tales" },
        stress_free_comfort: { ru: "Антистресс", en: "Stress-free comfort" },
        high_tempo: { ru: "Высокий темп", en: "High tempo" },
        kinetic_spectacle: { ru: "Драйв и зрелищность", en: "Kinetic spectacle" },
        fighting_spirit: { ru: "Боевой дух", en: "Fighting spirit" },
        future_genres: { ru: "Жанры будущего", en: "Genres of the future" },
        tech_and_space: { ru: "Технологии и космос", en: "Tech and space" },
        expansive_horizons: { ru: "Широкий горизонт", en: "Expansive horizons" },
        all_formats: { ru: "Все форматы", en: "All formats" },
        no_genre_limits: { ru: "Без жанровых рамок", en: "No genre limits" },
        eclectic_appetite: { ru: "Энциклопедичность", en: "Eclectic appetite" },
        mindful_pace: { ru: "Спокойный темп", en: "Mindful pace" },
        depth_over_speed: { ru: "Глубина, а не скорость", en: "Depth over speed" },
        intentional_curation: { ru: "Осознанный выбор", en: "Intentional curation" },
      },
      radarTitle: { ru: "Радар вкуса", en: "Taste radar" },
      radarHint: {
        ru: "Площадь — доля жанра в библиотеке, ★ — средняя ваша оценка",
        en: "Area — the genre's share of your library, ★ — your average score",
      },
      divergenceTitle: {
        ru: "Я против всего мира",
        en: "Me against the world",
      },
      hiddenGem: { ru: "Мой тайный шедевр", en: "My hidden gem" },
      hiddenGemHint: {
        ru: "Ваша оценка заметно выше мировой",
        en: "Your score towers over the world's",
      },
      disappointment: { ru: "Главное разочарование", en: "The big letdown" },
      disappointmentHint: {
        ru: "Мир в восторге, а вы — нет",
        en: "The world loved it, you didn't",
      },
      yourScore: { ru: "Ваша оценка", en: "Your score" },
      worldScore: { ru: "Мировая оценка", en: "World rating" },
      divergenceBadge: { ru: "Разрыв", en: "Gap" },
      divergenceEmpty: {
        ru: "Пока нет тайтлов с оценкой и внешним рейтингом.",
        en: "No titles with both your score and a world rating yet.",
      },
      sunkCostTitle: {
        ru: "Синдром потерянного времени",
        en: "Lost time syndrome",
      },
      sunkCostMessage: {
        ru: (hours: string, percent: string) =>
          `${hours} ч. (${percent}% всего времени) ушло на непонравившиеся или брошенные произведения`,
        en: (hours: string, percent: string) =>
          `${hours} h (${percent}% of your total time) went to titles you didn't enjoy or dropped`,
      },
      sunkCostTitlesCount: {
        ru: (count: number) => `тайтлов в убыточной зоне: ${count}`,
        en: (count: number) => `titles in the red zone: ${count}`,
      },
      sunkCostAdvice: {
        ru: "Смелее бросайте то, что не приносит радости — впереди тысячи отличных историй.",
        en: "Don't be afraid to drop what brings no joy — thousands of great stories lie ahead.",
      },
      sunkCostOther: { ru: "Остальное", en: "Other" },
      paradoxTitle: { ru: "Парадокс жанров", en: "Genre paradox" },
      paradoxCompletion: { ru: "Завершение", en: "Completion" },
      paradoxDrop: { ru: "Дроп", en: "Dropped" },
      eraTitle: { ru: "Золотая эпоха", en: "Golden era" },
      eraHint: {
        ru: "Десятилетия ваших любимых произведений (оценка 8+ или завершенные)",
        en: "Decades of your favorite titles (rated 8+ or completed)",
      },
      eras: {
        "pre-1980": { ru: "До 1980-х", en: "Before 1980" },
        "1980s": { ru: "1980-е", en: "1980s" },
        "1990s": { ru: "1990-е", en: "1990s" },
        "2000s": { ru: "2000-е", en: "2000s" },
        "2010s": { ru: "2010-е", en: "2010s" },
        "2020s": { ru: "2020-е", en: "2020s" },
      },
      emptyData: {
        ru: "Недостаточно данных — добавьте и оцените тайтлы, чтобы профиль вкуса раскрылся.",
        en: "Not enough data yet — add and rate titles to reveal your taste profile.",
      },
      dropAnalytics: {
        title: { ru: "Анатомия дропа", en: "Drop Analysis" },
        noReturnTitle: { ru: "Точка невозврата", en: "Point of No Return" },
        earlyDrop: { ru: "Ранний дроп (<20%)", en: "Early drop (<20%)" },
        midDrop: { ru: "В середине (20–70%)", en: "Midway (20–70%)" },
        lateDrop: { ru: "В шаге от финала (>70%)", en: "Near the end (>70%)" },
        avgDropText: {
          ru: (avg: number | string) => `В среднем вы бросаете произведения на ${avg}% пути`,
          en: (avg: number | string) => `On average, you drop titles at ${avg}% of progress`,
        },
        topReasonsTitle: { ru: "Топ причин дропа", en: "Top drop reasons" },
        insight: {
          ru: "Вы не боитесь бросать скучное в самом начале — это экономит сотни часов жизни для действительно любимых историй.",
          en: "You are not afraid to drop boring titles early — saving hundreds of hours for stories you truly love.",
        },
        totalDropped: {
          ru: (count: number) => `Всего брошено: ${count}`,
          en: (count: number) => `Total dropped: ${count}`,
        },
        empty: {
          ru: "Нет брошенных тайтлов — все начатое доведено до конца или отложено.",
          en: "No dropped titles yet — everything started is finished or on hold.",
        },
      },
    },
  },
  dropReason: {
    modalTitle: {
      ru: "Почему вы решили бросить?",
      en: "Why did you drop this?",
    },
    notesPlaceholder: {
      ru: "Короткая заметка (опционально)...",
      en: "Short note (optional)...",
    },
    save: { ru: "Сохранить", en: "Save" },
    skip: { ru: "Пропустить", en: "Skip" },
    deleteReason: { ru: "Удалить причину", en: "Remove reason" },
    changeReason: { ru: "Изменить причину", en: "Change reason" },
    reasonLabel: { ru: "Причина", en: "Reason" },
    badgePrefix: { ru: "Причина: ", en: "Reason: " },
    reasons: {
      boring: { ru: "Скучно / Затянуто", en: "Boring / Dragged out" },
      lost_interest: {
        ru: "Пропал интерес / Остыл",
        en: "Lost interest / Grew cold",
      },
      bad_plot: {
        ru: "Разочаровал сюжет / Слитый финал",
        en: "Disappointing plot / Ruined ending",
      },
      annoying_characters: {
        ru: "Бесячие персонажи / Клише",
        en: "Annoying characters / Cliches",
      },
      no_time: { ru: "Нехватка времени / Усталость", en: "No time / Burnout" },
      too_hard: {
        ru: "Непроходимо / Слишком сложно",
        en: "Too hard / Unbeatable",
      },
      grind: {
        ru: "Унылый гринд / Однообразие",
        en: "Tiresome grind / Repetitive",
      },
      bad_perf: {
        ru: "Баги / Плохая оптимизация",
        en: "Bugs / Poor optimization",
      },
      bad_translation: {
        ru: "Ужасный / Машинный перевод",
        en: "Terrible / Machine translation",
      },
      art_downgrade: { ru: "Испортилась рисовка", en: "Art downgrade" },
      abandoned: {
        ru: "Заброшено автором / Заморожено",
        en: "Abandoned / On hiatus",
      },
      fillers: { ru: "Филлеры / Вода", en: "Fillers / Padding" },
      other: { ru: "Другая причина", en: "Other reason" },
      unspecified: { ru: "Не указана", en: "Not specified" },
    },
  },
  card: {
    volume: {
      ru: (volume: number) => `Том ${volume}`,
      en: (volume: number) => `Volume ${volume}`,
    },
    pages: {
      ru: (current: number, total: number) => `${current} / ${total} стр.`,
      en: (current: number, total: number) => `${current} / ${total} pp.`,
    },
    chapters: {
      ru: (current: number, total: number | null) =>
        `${current} / ${total && total > 0 ? total : "—"} гл.`,
      en: (current: number, total: number | null) =>
        `${current} / ${total && total > 0 ? total : "—"} ch.`,
    },
    hours: {
      ru: (hours: number) => `${hours} ч.`,
      en: (hours: number) => `${hours} h`,
    },
    episodes: {
      ru: (current: number, total: number) => `${current} / ${total > 0 ? total : "—"} эп.`,
      en: (current: number, total: number) => `${current} / ${total > 0 ? total : "—"} ep.`,
    },
    movie: {
      ru: (minutes: number) => `${minutes} мин.`,
      en: (minutes: number) => `${minutes} min`,
    },
    deleteAria: {
      ru: (title: string) => `Удалить ${title}`,
      en: (title: string) => `Delete ${title}`,
    },
    openDetails: {
      ru: (title: string) => `Открыть ${title}`,
      en: (title: string) => `Open ${title}`,
    },
    confirmDelete: {
      ru: (title: string) => `Удалить «${title}»?`,
      en: (title: string) => `Delete “${title}”?`,
    },
    decrement: { ru: "Уменьшить прогресс", en: "Decrease progress" },
    increment: { ru: "Увеличить прогресс", en: "Increase progress" },
  },
  searchModal: {
    eyebrow: { ru: "Внешние базы", en: "External databases" },
    title: { ru: "Поиск тайтлов", en: "Search titles" },
    categoriesLabel: { ru: "Категории поиска", en: "Search categories" },
    inputLabel: { ru: "Поиск тайтла", en: "Search titles" },
    allCategories: { ru: "Все", en: "All" },
    placeholder: {
      ru: (category: string) => `Поиск: ${category.toLowerCase()}…`,
      en: (category: string) => `Search: ${category.toLowerCase()}…`,
    },
    emptyQueryTitle: {
      ru: "Введите название для поиска…",
      en: "Enter a title to search…",
    },
    emptyQueryHint: {
      ru: "Минимум 2 символа — результаты подтянутся из внешних баз.",
      en: "At least 2 characters — results come from external databases.",
    },
    searching: { ru: "Идёт поиск…", en: "Searching…" },
    errorHint: {
      ru: "Проверьте соединение и попробуйте другой запрос.",
      en: "Check your connection or try a different query.",
    },
    emptyTitle: { ru: "Ничего не найдено", en: "Nothing found" },
    emptyHint: {
      ru: "Попробуйте изменить запрос или выбрать другую категорию.",
      en: "Try a different query or switch categories.",
    },
    inLibrary: { ru: "В библиотеке", en: "In library" },
    added: { ru: "Добавлено", en: "Added" },
    goToTitle: { ru: "Перейти к тайтлу", en: "Go to title" },
    unknownAuthor: { ru: "Неизвестный автор", en: "Unknown author" },
    countUnits: {
      anime: { ru: "эп.", en: "ep." },
      manga: { ru: "гл.", en: "ch." },
      movie: { ru: "мин.", en: "min" },
      tvshow: { ru: "эп.", en: "ep." },
      game: { ru: "ч.", en: "h" },
      book: { ru: "стр.", en: "pp." },
    },
    showMoreCount: {
      ru: (count: number) => `Показать больше (${count})`,
      en: (count: number) => `Show more (${count})`,
    },
    preview: { ru: "Подробнее", en: "Details" },
    sourceLabel: { ru: "Источник", en: "Source" },
    allSources: { ru: "Все / По приоритету", en: "All / By priority" },
    creatorFilter: {
      ru: (name: string) => `Фильтр по создателю: ${name}`,
      en: (name: string) => `Creator filter: ${name}`,
    },
    resetCreatorFilter: {
      ru: "Вернуться к обычному поиску",
      en: "Back to a regular search",
    },
  },
  createModal: {
    eyebrow: { ru: "Новая запись", en: "New entry" },
    title: { ru: "Добавить медиа", en: "Add media" },
    fields: {
      type: { ru: "Тип", en: "Type" },
      title: { ru: "Название", en: "Title" },
      coverUrl: { ru: "Обложка", en: "Cover" },
      platform: { ru: "Платформа", en: "Platform" },
      hoursPlayed: { ru: "Часы", en: "Hours" },
      author: { ru: "Автор", en: "Author" },
      totalPages: { ru: "Страницы", en: "Pages" },
      totalChapters: { ru: "Главы", en: "Chapters" },
      currentVolume: { ru: "Текущий том", en: "Current volume" },
      isAnime: { ru: "Это аниме?", en: "Is it anime?" },
      studio: { ru: "Студия", en: "Studio" },
      durationMinutes: { ru: "Длительность (мин.)", en: "Duration (min.)" },
      network: { ru: "Сеть", en: "Network" },
      notes: { ru: "Заметки", en: "Notes" },
      season: { ru: "Сезон", en: "Season" },
      episodes: { ru: "Эпизоды", en: "Episodes" },
      score: { ru: "Оценка", en: "Score" },
      startedAt: { ru: "Начало", en: "Started at" },
      finishedAt: { ru: "Завершение", en: "Finished at" },
    },
    placeholders: {
      title: {
        ru: "Например, The Witcher 3",
        en: "For example, The Witcher 3",
      },
      author: { ru: "Автор", en: "Author" },
      platform: {
        ru: "PC, PlayStation, Switch",
        en: "PC, PlayStation, Switch",
      },
      studio: { ru: "Студия", en: "Studio" },
      network: {
        ru: "Стриминг или телеканал",
        en: "Streaming service or TV channel",
      },
      notes: { ru: "Личные заметки", en: "Personal notes" },
      season: { ru: "Название сезона", en: "Season title" },
    },
    addSeason: { ru: "Добавить сезон", en: "Add season" },
    validation: {
      titleRequired: { ru: "Укажите название.", en: "Please provide a title." },
      coverUrlInvalid: {
        ru: "Обложка: ссылка http(s) или локальный путь, например /media-assets/...",
        en: "Cover: an http(s) link or a local path, e.g. /media-assets/...",
      },
    },
  },
  detailModal: {
    typeLabel: { ru: "Тип", en: "Type" },
    scoreEmpty: { ru: "Без оценки", en: "Not rated" },
    dateEmpty: { ru: "—", en: "—" },
    valueEmpty: { ru: "—", en: "—" },
    startedAt: { ru: "Начало", en: "Started at" },
    finishedAt: { ru: "Завершение", en: "Finished at" },
    studio: { ru: "Студия", en: "Studio" },
    author: { ru: "Автор", en: "Author" },
    platform: { ru: "Платформа", en: "Platform" },
    network: { ru: "Сеть", en: "Network" },
    director: { ru: "Режиссёр", en: "Director" },
    edit: { ru: "Редактировать", en: "Edit" },
    delete: { ru: "Удалить", en: "Delete" },
  },
  detail: {
    eyebrow: { ru: "Карточка медиа", en: "Media details" },
    autoRefreshTitle: { ru: "Автообновление", en: "Auto-refresh" },
    autoRefreshInterval: {
      ru: (days: number) => `раз в ${days} дн.`,
      en: (days: number) => `every ${days} days`,
    },
    autoRefreshHiatus: { ru: "На паузе у автора", en: "On hiatus" },
    autoRefreshFinished: { ru: "Релиз завершён", en: "Release finished" },
    autoRefreshFinishedHint: {
      ru: "Автопроверка отключена",
      en: "Auto-check disabled",
    },
    autoRefreshCheckNow: {
      ru: "Проверить обновления",
      en: "Check for updates",
    },
    autoRefreshDone: {
      ru: "Автопроверка выполнена",
      en: "Auto-check finished",
    },
    progressTitle: { ru: "Ваш прогресс", en: "Your progress" },
    progressUnsupported: {
      ru: "Для этого типа прогресс не ведётся.",
      en: "Progress is not tracked for this type.",
    },
    actionsTitle: { ru: "Действия", en: "Actions" },
    detailsTitle: { ru: "Характеристики", en: "Details" },
    originalTitle: { ru: "Оригинальное название", en: "Original title" },
    synopsisTitle: { ru: "Синопсис", en: "Synopsis" },
    noSynopsis: {
      ru: "Описание отсутствует.",
      en: "No description available.",
    },
    readMore: { ru: "Читать далее", en: "Read more" },
    collapse: { ru: "Свернуть", en: "Collapse" },
    translate: { ru: "Перевести", en: "Translate" },
    translating: { ru: "Перевод…", en: "Translating…" },
    showOriginal: { ru: "Оригинал", en: "Original" },
    minPerEp: { ru: "мин. / эп.", en: "min / ep" },
    minShort: { ru: "мин.", en: "min" },
    externalRating: { ru: "Рейтинг базы", en: "Database rating" },
    externalRatingEmpty: { ru: "Нет данных", en: "No data" },
    votes: {
      ru: (count: number) => `Голосов: ${count}`,
      en: (count: number) => `Votes: ${count}`,
    },
    yourRating: { ru: "Ваша личная оценка", en: "Your personal score" },
    byCriteria: { ru: "По критериям", en: "Detailed" },
    detailedScoreTitle: { ru: "Детальная оценка", en: "Detailed score" },
    detailedAverage: { ru: "Среднее", en: "Average" },
    applyScore: { ru: "Применить", en: "Apply" },
    saveDetailedScore: {
      ru: (score: number) => `Сохранить (${score} ★)`,
      en: (score: number) => `Save (${score} ★)`,
    },
    saveCriteriaOnly: { ru: "Только критерии", en: "Criteria only" },
    clearRating: { ru: "Сбросить", en: "Clear" },
    ratingValue: {
      ru: (score: number) => `${score} / 10`,
      en: (score: number) => `${score} / 10`,
    },
    starAria: {
      ru: (score: number) => `Поставить оценку ${score}`,
      en: (score: number) => `Rate ${score}`,
    },
    relatedTitle: { ru: "Связанные тайтлы", en: "Related titles" },
    relatedEmpty: {
      ru: "Этот тайтл не входит ни в одну франшизу.",
      en: "This title does not belong to a franchise.",
    },
    notesHint: {
      ru: "Личные мысли, впечатления и черновик отзыва.",
      en: "Personal thoughts, impressions and review draft.",
    },
    saveNotes: { ru: "Сохранить заметки", en: "Save notes" },
    notesSaved: { ru: "Заметки сохранены.", en: "Notes saved." },
    quickFacts: { ru: "Быстрые факты", en: "Quick facts" },
    addNoteHint: {
      ru: "+ Добавить личные заметки или впечатления",
      en: "+ Add personal notes or impressions",
    },
    yourNotes: { ru: "Ваши заметки и мысли", en: "Your notes and thoughts" },
    notesPlaceholder: {
      ru: "У вас пока нет личных заметок по этому тайтлу. Нажмите, чтобы записать впечатления или черновик отзыва...",
      en: "You don't have personal notes for this title yet. Click to save your impressions or a draft review...",
    },
    quotesTitle: { ru: "ЦИТАТЫ И ВЫПИСКИ", en: "QUOTES & HIGHLIGHTS" },
    quotesAdd: { ru: "Добавить цитату", en: "Add quote" },
    quotesPlaceholder: {
      ru: "Введите цитату или запоминающийся отрывок...",
      en: "Enter a quote or memorable excerpt...",
    },
    quotesContextPlaceholder: {
      ru: "Страница или глава (напр. стр. 84)",
      en: "Page or chapter (e.g. p. 84)",
    },
    quotesSave: { ru: "Сохранить цитату", en: "Save quote" },
    quotesCancel: { ru: "Отмена", en: "Cancel" },
    quotesEmpty: {
      ru: "У вас пока нет сохранённых цитат. Нажмите +, чтобы выписать любимый отрывок из книги.",
      en: "You have no saved quotes yet. Click + to save your favorite excerpt.",
    },
    trailerNotFound: { ru: "Трейлер не найден", en: "Trailer not found" },
    trailerTitle: { ru: "Трейлер", en: "Trailer" },
    castTitle: { ru: "В главных ролях", en: "Cast" },
    voiceActorsTitle: { ru: "Актёры озвучки (сэйю)", en: "Voice Cast" },
    charactersTitle: { ru: "Персонажи", en: "Characters" },
    roleMain: { ru: "Главный", en: "Main" },
    roleSupporting: { ru: "Второстепенный", en: "Supporting" },
    compactViewTooltip: { ru: "Компактный вид", en: "Compact view" },
    largeViewTooltip: { ru: "Крупный вид", en: "Large view" },
    formatMovie: { ru: "Фильм", en: "Movie" },
    formatSeries: { ru: "Сериал", en: "Series" },
    formatAnime: { ru: "Аниме", en: "Anime" },
    formatManga: { ru: "Манга", en: "Manga" },
    formatBook: { ru: "Книга", en: "Book" },
    formatGame: { ru: "Игра", en: "Game" },
    statusOngoing: { ru: "Онгоинг", en: "Ongoing" },
    statusFinished: { ru: "Завершён", en: "Finished" },
    statusAnnounced: { ru: "Анонс", en: "Announced" },
    originalLanguage: { ru: "Язык", en: "Language" },
    countryOfOrigin: { ru: "Страна", en: "Country" },
    source: { ru: "Источник данных", en: "Data source" },
    hoursLabel: { ru: "Время в игре", en: "Time played" },
    pagesLabel: { ru: "Страницы", en: "Pages" },
    chaptersLabel: { ru: "Главы", en: "Chapters" },
    volumeLabel: { ru: "Текущий том", en: "Current volume" },
    durationLabel: { ru: "Хронометраж", en: "Runtime" },
    episodesLabel: { ru: "Серии", en: "Episodes" },
    notFound: { ru: "Тайтл не найден.", en: "Title not found." },
    historyTitle: { ru: "Ваша история", en: "Your history" },
    startedLabel: { ru: "Начало", en: "Started" },
    endedLabel: { ru: "Завершение", en: "Ended" },
    progressShort: { ru: "Прогресс", en: "Progress" },
    formatLabel: { ru: "Формат", en: "Format" },
    mangaFormats: {
      manga: { ru: "Манга", en: "Manga" },
      manhwa: { ru: "Манхва", en: "Manhwa" },
      manhua: { ru: "Маньхуа", en: "Manhua" },
      oel: { ru: "Oel-манга", en: "Oel manga" },
    },
    startDateLabel: { ru: "Дата начала", en: "Start date" },
    endDateLabel: { ru: "Дата окончания", en: "End date" },
    providerLabel: { ru: "Провайдер", en: "Provider" },
    genresLabel: { ru: "Жанры", en: "Genres" },
    tagsLabel: { ru: "Теги", en: "Tags" },
    releaseDateLabel: { ru: "Дата релиза", en: "Release date" },
    addToLists: { ru: "В списки", en: "Add to lists" },
    activity: { ru: "Активность", en: "Activity" },
    markWatched: { ru: "Отметить просмотренной", en: "Mark as watched" },
    episodeTitle: {
      ru: (episode: number) => `Серия ${episode}`,
      en: (episode: number) => `Episode ${episode}`,
    },
    watchAction: { ru: "Отметить как просмотрено", en: "Mark as watched" },
    updateMetadata: { ru: "Обновить метаданные", en: "Update metadata" },
    updatingMetadata: { ru: "Обновление…", en: "Updating…" },
    metadataUpdated: {
      ru: "Метаданные обновлены.",
      en: "Metadata updated successfully.",
    },
    metadataMergeKept: {
      ru: "Пустые поля обновлены, ваши правки сохранены.",
      en: "Empty fields updated, your edits kept.",
    },
    overwriteTitle: {
      ru: "Обнаружены ваши ручные изменения",
      en: "Your manual edits were detected",
    },
    overwriteHint: {
      ru: "Что сделать с данными, которые вы изменяли вручную?",
      en: "What should happen to the fields you edited by hand?",
    },
    overwriteSafe: {
      ru: "Обновить только пустые (сохранить мои правки)",
      en: "Update only empty (keep my edits)",
    },
    overwriteFull: {
      ru: "Перезаписать всё из источника",
      en: "Overwrite everything from the source",
    },
    fillMissing: { ru: "Дополнить данные…", en: "Fill missing data…" },
    fillMissingTitle: { ru: "Дополнить данные", en: "Fill missing data" },
    fillMissingHint: {
      ru: "Заполнит только пустые поля из выбранного источника. Уже заполненное не изменится.",
      en: "Only empty fields are filled from the chosen source. Anything already filled stays as is.",
    },
    fillMissingSource: { ru: "Источник", en: "Source" },
    fillMissingRunning: { ru: "Дополняю поля…", en: "Filling gaps…" },
    fillMissingDone: {
      ru: "Пустые поля дополнены из источника.",
      en: "Empty fields filled from the source.",
    },
    fillMissingSourcesFailed: {
      ru: "Не удалось загрузить список источников.",
      en: "Could not load the source list.",
    },
    changeSource: { ru: "Сменить источник", en: "Change source" },
    watchedOnLabel: { ru: "Где смотрено", en: "Watched on" },
    watchedOnPlaceholder: {
      ru: "Выберите или введите",
      en: "Pick or type",
    },
    platformNotSelected: { ru: "Не выбрана", en: "Not selected" },
    rateButton: { ru: "Оценить", en: "Rate" },
    markSeasonWatched: { ru: "Отметить сезон", en: "Mark season watched" },
    resetSeason: { ru: "Сбросить сезон", en: "Reset season" },
    sortAsc: { ru: "С начала", en: "From start" },
    sortDesc: { ru: "С конца", en: "From end" },
    tabOverview: { ru: "Обзор", en: "Overview" },
    tabEpisodes: { ru: "Эпизоды", en: "Episodes" },
    tabVolumes: { ru: "Тома", en: "Volumes" },
    volumesLabel: { ru: "Тома", en: "Volumes" },
    romajiTitle: { ru: "Название на ромадзи", en: "Romaji title" },
    volumeProgress: { ru: "Прогресс тома", en: "Volume progress" },
    addVolume: { ru: "Добавить том", en: "Add volume" },
    markVolumeComplete: {
      ru: "Отметить том прочитанным",
      en: "Mark volume completed",
    },
    markRead: { ru: "Отметить как прочитано", en: "Mark as read" },
    unmarkRead: { ru: "Отменить отметку", en: "Unmark" },
    tabRelatedMedia: { ru: "Связанное", en: "Related" },
    tabRecommendations: { ru: "Рекомендации", en: "Recommendations" },
    bannerNextEpisode: { ru: "Следующая серия", en: "Next episode" },
    bannerCompleted: {
      ru: "Все серии просмотрены",
      en: "All episodes watched",
    },
    noRecommendations: {
      ru: "Рекомендации отсутствуют.",
      en: "No recommendations found.",
    },
    userScoreLabel: { ru: "Ваша оценка", en: "Your score" },
    viewGrouped: { ru: "По группам", en: "Grouped" },
    viewTimeline: { ru: "Хронология", en: "Timeline" },
    viewGrid: { ru: "Сетка", en: "Grid" },
    relatedSubtitle: {
      ru: "Связанные части франшизы, сиквелы, спин-оффы и адаптации",
      en: "Related franchise entries, sequels, spin-offs and adaptations",
    },
    cachedForDays: { ru: "Кэшируется на 30 дней", en: "Cached for 30 days" },
    currentTitleBadge: { ru: "Текущий тайтл", en: "Current title" },
    overviewBadge: { ru: "Обзор", en: "Overview" },
    unwatchAction: { ru: "Отменить просмотр", en: "Unmark watched" },
    groupMain: {
      ru: "Основные истории (Сиквелы и Приквелы)",
      en: "Main Story (Sequels & Prequels)",
    },
    groupSpinoffs: {
      ru: "Спин-оффы и Истории",
      en: "Spin-offs & Side Stories",
    },
    groupAdaptations: { ru: "Адаптации и Манга", en: "Adaptations & Manga" },
    groupOthers: { ru: "Рекапы и Другое", en: "Recaps & Others" },
    relations: {
      sequel: { ru: "Сиквел", en: "Sequel" },
      prequel: { ru: "Приквел", en: "Prequel" },
      adaptation: { ru: "Адаптация", en: "Adaptation" },
      sideStory: { ru: "Спин-офф", en: "Side Story" },
      spinOff: { ru: "Спин-офф", en: "Spin-off" },
      summary: { ru: "Рекап", en: "Recap" },
      alternative: { ru: "Альтернатива", en: "Alternative" },
      character: { ru: "Спецвыпуск", en: "Special" },
      other: { ru: "Связанное", en: "Related" },
    },
    formats: {
      movie: { ru: "Фильм", en: "Movie" },
      tv: { ru: "Сериал", en: "TV Series" },
      ova: { ru: "OVA", en: "OVA" },
      ona: { ru: "ONA", en: "ONA" },
      special: { ru: "Спешл", en: "Special" },
      manga: { ru: "Манга", en: "Manga" },
      novel: { ru: "Ранобэ", en: "Light Novel" },
      oneShot: { ru: "Ваншот", en: "One-shot" },
      music: { ru: "Клип", en: "Music Video" },
    },
    releaseStatuses: {
      releasing: { ru: "Онгоинг", en: "Releasing" },
      finished: { ru: "Завершён", en: "Finished" },
      notYetReleased: { ru: "Анонс", en: "Not Yet Released" },
      cancelled: { ru: "Отменён", en: "Cancelled" },
      hiatus: { ru: "Приостановлен", en: "On Hiatus" },
    },
    previewModal: {
      year: { ru: "Год", en: "Year" },
      studio: { ru: "Студия / Сеть", en: "Studio / Network" },
      author: { ru: "Автор", en: "Author" },
      platform: { ru: "Платформа", en: "Platform" },
      count: { ru: "Количество", en: "Count" },
      description: { ru: "Описание", en: "Description" },
      noRatings: { ru: "Рейтинг: Нет данных", en: "Rating: No data" },
      noDescription: {
        ru: "Описание отсутствует",
        en: "No description available",
      },
      noData: { ru: "Нет данных", en: "No data" },
      episodesList: {
        ru: (count: number) => `Список эпизодов (${count})`,
        en: (count: number) => `Episode list (${count})`,
      },
      initialStatus: { ru: "Начальный статус", en: "Initial status" },
      addToLibrary: { ru: "Добавить в библиотеку", en: "Add to library" },
      addingToLibrary: { ru: "Добавление…", en: "Adding…" },
      episodesCount: {
        ru: (count: number) => `Эпизодов: ${count}`,
        en: (count: number) => `Episodes: ${count}`,
      },
      chaptersCount: {
        ru: (count: number) => `Глав: ${count}`,
        en: (count: number) => `Chapters: ${count}`,
      },
    },
  },
  importModal: {
    title: { ru: "Импорт медиатеки", en: "Import your library" },
    description: {
      ru: "Перенесите прогресс, оценки и списки из популярных сервисов или своих файлов.",
      en: "Transfer progress, ratings and lists from popular services or custom files.",
    },
    source: { ru: "1. Выберите источник", en: "1. Choose a source" },
    fileLabel: { ru: "2. Файл или профиль", en: "2. File or profile" },
    dropFile: {
      ru: "Перетащите файл сюда или нажмите для выбора",
      en: "Drop a file here or click to browse",
    },
    formats: {
      ru: (formats: string) => `Поддерживаемые форматы: ${formats}`,
      en: (formats: string) => `Supported formats: ${formats}`,
    },
    helpMal: {
      ru: "MyAnimeList: Profile → Anime List / Manga List → Export. Поддерживаются XML и JSON.",
      en: "MyAnimeList: Profile → Anime List / Manga List → Export. XML and JSON are supported.",
    },
    helpShikimori: {
      ru: "Shikimori: экспорт списка из профиля в XML или JSON.",
      en: "Shikimori: export your list from your profile as XML or JSON.",
    },
    helpLetterboxd: {
      ru: "Letterboxd: Settings → Data → Export your data (diary.csv / watched.csv / ratings.csv).",
      en: "Letterboxd: Settings → Data → Export your data (diary.csv / watched.csv / ratings.csv).",
    },
    helpGoodreads: {
      ru: "Goodreads: My Books → Import and Export → Export Library.",
      en: "Goodreads: My Books → Import and Export → Export Library.",
    },
    helpSteam: {
      ru: "Профиль и игры должны быть открыты. Steam Web API key можно получить здесь.",
      en: "Your profile and games must be public. Get a Steam Web API key here.",
    },
    steamProfile: {
      ru: "SteamID64 или ссылка на публичный профиль",
      en: "SteamID64 or public profile URL",
    },
    checkProfile: { ru: "Проверить", en: "Check" },
    profileValid: {
      ru: "Формат SteamID64 или профиля корректен.",
      en: "SteamID64 or profile format looks valid.",
    },
    steamApiKey: {
      ru: "Steam Web API key (необязательно, если настроен на сервере)",
      en: "Steam Web API key (optional if configured on the server)",
    },
    steamKeyConfigured: {
      ru: "✓ API-ключ настроен на сервере",
      en: "✓ API key is configured on the server",
    },
    saveSteamKey: {
      ru: "Сохранить ключ в настройках",
      en: "Save key to settings",
    },
    options: { ru: "3. Настройки импорта", en: "3. Import options" },
    skipDuplicates: {
      ru: "Пропускать уже существующие тайтлы",
      en: "Skip titles already in my library",
    },
    addToList: {
      ru: "Добавить импортированные тайтлы в список",
      en: "Add imported titles to a list",
    },
    existingList: { ru: "В существующий список", en: "Use an existing list" },
    newList: { ru: "Создать новый список", en: "Create a new list" },
    selectList: { ru: "Выберите список…", en: "Select a list…" },
    defaultList: {
      ru: (provider: string) => `Импорт ${provider}`,
      en: (provider: string) => `${provider} import`,
    },
    selectFileError: {
      ru: "Выберите файл для импорта.",
      en: "Choose a file to import.",
    },
    invalidFile: {
      ru: "Формат файла не поддерживается для этого источника.",
      en: "This file format is not supported for this source.",
    },
    steamRequired: {
      ru: "Введите SteamID64 или ссылку на профиль.",
      en: "Enter a SteamID64 or profile URL.",
    },
    chooseListError: { ru: "Выберите список.", en: "Choose a list." },
    listNameError: {
      ru: "Введите название нового списка.",
      en: "Enter a name for the new list.",
    },
    failed: { ru: "Не удалось выполнить импорт.", en: "The import failed." },
    start: { ru: "Начать импорт", en: "Start import" },
    importing: { ru: "Импорт…", en: "Importing…" },
    success: { ru: "Импорт завершён", en: "Import complete" },
    total: { ru: "Всего найдено", en: "Total found" },
    imported: { ru: "Успешно импортировано", en: "Imported" },
    skipped: { ru: "Пропущено дубликатов", en: "Duplicates skipped" },
    openList: { ru: "Перейти в список", en: "Open list" },
    subtitleAnilist: {
      ru: "JSON или профиль пользователя",
      en: "JSON or user profile",
    },
    subtitleMangalib: {
      ru: "MangaLib / AnimeLib / RanobeLib",
      en: "MangaLib / AnimeLib / RanobeLib",
    },
    subtitleCustom: {
      ru: "Универсальный JSON / CSV",
      en: "Universal JSON / CSV",
    },
    helpAnilist: {
      ru: "AniList: Settings → Account → Export Data. Либо введите никнейм профиля — список загрузится через публичный API.",
      en: "AniList: Settings → Account → Export Data — or enter a profile username to fetch it via the public API.",
    },
    helpMangalib: {
      ru: "Быстрый импорт закладок всей экосистемы SocialLib (MangaLib, AnimeLib, RanobeLib, SlashLib, HentaiLib)",
      en: "Fast import for the entire SocialLib ecosystem (MangaLib, AnimeLib, RanobeLib, SlashLib, HentaiLib)",
    },
    helpCustom: {
      ru: "Импортируйте собственный JSON или CSV с колонками: title, type, status, score, progress, totalCount, author / studio / director, releaseYear.",
      en: "Import your own JSON or CSV with the columns: title, type, status, score, progress, totalCount, author / studio / director, releaseYear.",
    },
    anilistFileTab: { ru: "Загрузить JSON-файл", en: "Upload JSON file" },
    anilistProfileTab: { ru: "По никнейму профиля", en: "By profile username" },
    anilistUsername: { ru: "Никнейм AniList", en: "AniList username" },
    anilistUsernamePlaceholder: { ru: "Например, Mai-kun", en: "e.g. Mai-kun" },
    anilistUsernameError: {
      ru: "Введите никнейм пользователя AniList.",
      en: "Enter an AniList username.",
    },
    import: { ru: "Импортировать", en: "Import" },
    showTemplate: {
      ru: "Показать пример шаблона",
      en: "Show template example",
    },
    supportsMangaLibFiles: {
      ru: "Поддерживаются файлы tsundoku-sociallib.json",
      en: "Supports tsundoku-sociallib.json files",
    },
    customFoldersTitle: {
      ru: "Настройка пользовательских списков",
      en: "Custom Lists Setup",
    },
    customFoldersExplanation: {
      ru: "В импорте найдены тайтлы из пользовательских папок SocialLib. Выберите статус и настройки создания списков для каждой папки:",
      en: "Found titles from custom SocialLib folders. Choose status and list options for each folder:",
    },
    customFoldersStatusLabel: {
      ru: "Статус в медиатеке",
      en: "Library status",
    },
    customFoldersCreateLists: {
      ru: "Создать такие же списки в Tsundoku и добавить туда эти тайтлы",
      en: "Create matching lists in Tsundoku and add these titles there",
    },
    customFoldersCreateListFor: {
      ru: (folder: string) => `Создать список «${folder}» в Tsundoku и добавить туда эти тайтлы`,
      en: (folder: string) => `Create «${folder}» list in Tsundoku and add these titles there`,
    },
    customFolderCountLabel: {
      ru: (count: number) => {
        const rem10 = count % 10;
        const rem100 = count % 100;
        let word = "тайтлов";
        if (rem10 === 1 && rem100 !== 11) word = "тайтл";
        else if (rem10 >= 2 && rem10 <= 4 && (rem100 < 10 || rem100 >= 20)) word = "тайтла";
        return `${count} ${word}`;
      },
      en: (count: number) => `${count} ${count === 1 ? "title" : "titles"}`,
    },
    continueImport: { ru: "Продолжить импорт", en: "Continue import" },
    statusPlanned: { ru: "В планах", en: "Planned" },
    statusOnHold: { ru: "На паузе", en: "On Hold" },
    statusInProgress: { ru: "В процессе", en: "In Progress" },
    statusDropped: { ru: "Брошено", en: "Dropped" },
    statusSkip: { ru: "Пропустить", en: "Skip" },
    hideTemplate: { ru: "Скрыть пример шаблона", en: "Hide template example" },
    templateJsonLabel: { ru: "Пример JSON", en: "JSON example" },
    templateCsvLabel: { ru: "CSV-заголовки", en: "CSV headers" },
    copyTemplate: { ru: "Скопировать пример JSON", en: "Copy JSON example" },
    templateCopied: { ru: "Пример скопирован", en: "Example copied" },
    templateCopyFailed: {
      ru: "Не удалось скопировать пример.",
      en: "Failed to copy the example.",
    },
    customTitle: { ru: "Свой файл", en: "Custom file" },
    steamProfileTab: { ru: "Публичный профиль", en: "Public profile" },
    steamFileTab: { ru: "JSON-файл", en: "JSON file" },
    fileSelected: { ru: "Файл выбран", en: "File selected" },
    changeFile: { ru: "Сменить файл", en: "Change file" },
    importAnother: { ru: "Импортировать ещё", en: "Import another" },
    optionsTitle: { ru: "Опции импорта", en: "Import options" },
    sourceTitle: { ru: "Выбор источника", en: "Source selection" },
    socialLibSites: {
      ru: "Сайты экосистемы SocialLib",
      en: "SocialLib Ecosystem Sites",
    },
    mangaLibSub: { ru: "Манга", en: "Manga" },
    animeLibSub: { ru: "Аниме", en: "Anime" },
    ranobeLibSub: { ru: "Ранобэ / Книги", en: "Light Novels / Books" },
    slashLibSub: { ru: "Слэш", en: "Slash" },
    hentaiLibSub: { ru: "18+", en: "18+" },
    listsToImport: {
      ru: "Какие списки импортировать:",
      en: "Lists to import:",
    },
    reading: { ru: "Читаю", en: "Reading" },
    planned: { ru: "В планах", en: "Plan to read" },
    completed: { ru: "Прочитано", en: "Completed" },
    favorites: { ru: "Любимые", en: "Favorites" },
    dropped: { ru: "Брошено", en: "Dropped" },
    customFolders: {
      ru: "Пользовательские папки",
      en: "Custom folders",
    },
    readingWatching: {
      ru: "Читаю / Смотрю",
      en: "Reading / Watching",
    },
    onHoldWaiting: {
      ru: "Отложено / Жду",
      en: "On Hold / Waiting",
    },
    droppedRemoved: {
      ru: "Брошено / Удалено",
      en: "Dropped / Removed",
    },
    instantCollector: {
      ru: "Мгновенный сборщик",
      en: "Instant Collector",
    },
    fileJsonCsv: {
      ru: "Файл .json / .csv",
      en: "File .json / .csv",
    },
    recommended: {
      ru: "Рекомендуется",
      en: "Recommended",
    },
    instantCollectorTitle: {
      ru: "Сбор закладок за 1 секунду прямо из браузера",
      en: "1-second bookmarks export directly from your browser",
    },
    instantCollectorDesc: {
      ru: "Обходит ограничения Cloudflare, моментально извлекая закладки со всех выбранных сайтов Lib с прогрессом, оценками и статусами.",
      en: "Bypasses Cloudflare restrictions, instantly exporting bookmarks from all chosen Lib sites with progress, scores, and statuses.",
    },
    oneClickNoF12: {
      ru: "1 клик без F12",
      en: "1 click without F12",
    },
    bookmarkletButton: {
      ru: "Кнопка-букмарклет для браузера",
      en: "Browser bookmarklet button",
    },
    linkCopied: {
      ru: "Ссылка скопирована!",
      en: "Link copied!",
    },
    copyBookmarkletLink: {
      ru: "Скопировать ссылку букмарклета",
      en: "Copy bookmarklet link",
    },
    bookmarkletInstruction: {
      ru: "Перетащите эту кнопку на панель закладок вашего браузера",
      en: "Drag this button to your browser bookmarks bar",
    },
    bookmarkletInstructionSuffix: {
      ru: ". Затем откройте любую страницу MangaLib, AnimeLib или RanobeLib и просто кликните по закладке!",
      en: ". Then open any page on MangaLib, AnimeLib, or RanobeLib and just click the bookmark!",
    },
    bookmarkletDragTooltip: {
      ru: "Зажмите и перетащите на панель закладок браузера (Ctrl+Shift+B)",
      en: "Click and drag to browser bookmarks bar (Ctrl+Shift+B)",
    },
    bookmarkletDragAlert: {
      ru: "📌 Перетащите эту кнопку мышкой на панель закладок браузера (Ctrl+Shift+B)!\n\nИли нажмите «Скопировать ссылку букмарклета» справа и создайте закладку вручную.",
      en: "📌 Drag this button to your browser bookmarks bar (Ctrl+Shift+B)!\n\nOr click 'Copy bookmarklet link' on the right to create the bookmark manually.",
    },
    bookmarkletButtonText: {
      ru: "📥 Tsundoku Импорт (перетащите в закладки)",
      en: "📥 Tsundoku Import (drag to bookmarks)",
    },
    bookmarkletDragHint: {
      ru: "← зажмите и потяните на панель закладок",
      en: "← drag and drop to your bookmarks bar",
    },
    step1Text: {
      ru: "Откройте страницу своего профиля или закладок на любом сайте Lib",
      en: "Open your profile or bookmarks page on any Lib website",
    },
    step2TextPre: {
      ru: "Нажмите на закладку в браузере (или откройте консоль",
      en: "Click the bookmark in your browser (or open dev console with",
    },
    step2TextMid: {
      ru: ", вставьте скрипт и нажмите",
      en: ", paste the script, and press",
    },
    step2TextPost: {
      ru: "). Букмарклет моментально выгрузит закладки.",
      en: "). The bookmarklet will instantly dump bookmarks.",
    },
    step3TextPre: {
      ru: "Если прямое сохранение заблокировано браузером — данные уже скопированы в буфер обмена: просто нажмите",
      en: "If direct upload was blocked by the browser, the data is already copied to clipboard: simply click",
    },
    step3TextBtn: {
      ru: "«Вставить из буфера и импортировать»",
      en: '"Paste from clipboard and import"',
    },
    step3TextPost: {
      ru: "ниже.",
      en: "below.",
    },
    scriptCopied: {
      ru: "Скрипт скопирован!",
      en: "Script copied!",
    },
    copyCollectorScript: {
      ru: "Скопировать скрипт сбора",
      en: "Copy collector script",
    },
    importingStatus: {
      ru: "Импортируем...",
      en: "Importing...",
    },
    pasteAndImport: {
      ru: "Вставить из буфера и импортировать",
      en: "Paste from clipboard and import",
    },
    selectedOf: {
      ru: (selected: number, total: number) => `Выбрано: ${selected} из ${total}`,
      en: (selected: number, total: number) => `Selected: ${selected} of ${total}`,
    },
    copyBookmarkletFailed: {
      ru: "Не удалось скопировать букмарклет в буфер обмена",
      en: "Failed to copy bookmarklet to clipboard",
    },
    copyScriptFailed: {
      ru: "Не удалось скопировать скрипт в буфер обмена",
      en: "Failed to copy script to clipboard",
    },
    clipboardUnavailable: {
      ru: "Буфер обмена недоступен в вашем браузере. Выберите способ «Файл» и загрузите сохраненный tsundoku-sociallib.json.",
      en: "Clipboard is unavailable in your browser. Choose 'File' tab and upload your tsundoku-sociallib.json.",
    },
    clipboardEmpty: {
      ru: "Буфер обмена пуст. Сначала скопируйте скрипт, выполните его в консоли любого Lib-сайта, а затем нажмите эту кнопку.",
      en: "Clipboard is empty. Copy and run the script on any Lib website first, then click this button.",
    },
    clipboardNoJson: {
      ru: "В буфере обмена нет JSON данных закладок. Убедитесь, что скрипт в консоли завершил сбор.",
      en: "Clipboard does not contain valid bookmark JSON. Make sure the collector script completed.",
    },
    skippedDuplicatesWithCount: {
      ru: (count: number) => `Пропущено дубликатов: ${count}`,
      en: (count: number) => `Duplicates skipped: ${count}`,
    },
    duplicatesWithTitles: {
      ru: (titles: string) => `Дубликаты: ${titles}`,
      en: (titles: string) => `Duplicates: ${titles}`,
    },
    customFolderDefaultName: {
      ru: "Пользовательская папка",
      en: "Custom folder",
    },
  },
  settingsModal: {
    title: { ru: "Настройки", en: "Settings" },
    tabs: {
      sources: { ru: "Источники", en: "Sources" },
      search: { ru: "Поиск", en: "Search" },
      backup: { ru: "Резервная копия", en: "Backup" },
      import: { ru: "Импорт", en: "Import" },
      reading: { ru: "Темп чтения", en: "Reading Speed" },
      apiTokens: { ru: "API и доступ", en: "API & Access" },
    },
    sources: {
      title: { ru: "Поддерживаемые источники", en: "Supported Sources" },
      description: {
        ru: "Источники данных для поиска и синхронизации метаданных.",
        en: "Metadata and rating providers supported by the application.",
      },
      filterLabel: { ru: "Фильтр по типу", en: "Filter by type" },
      filterAll: { ru: "Все типы", en: "All types" },
      noKeyRequired: { ru: "Ключ не требуется", en: "No API key needed" },
      keyRequired: { ru: "Требуется API ключ", en: "API key required" },
      optionalKey: { ru: "Ключ необязателен", en: "API key optional" },
      optionalKeyHint: {
        ru: "Ключ необязателен (поиск, обложки и достижения работают без него). Нужен только для импорта вашей библиотеки по SteamID",
        en: "API key is optional (search, covers & achievements work without it). Only needed for importing your library by SteamID",
      },
      keyConfigured: {
        ru: "Ключ настроен (зашифрован в SQLite)",
        en: "API key configured (encrypted in SQLite)",
      },
      keyMissing: { ru: "Ключ не задан", en: "API key missing" },
      inputPlaceholder: { ru: "Введите API ключ...", en: "Enter API key..." },
      saveKey: { ru: "Сохранить ключ", en: "Save key" },
      saved: {
        ru: "Ключ успешно сохранён и зашифрован в базе данных",
        en: "API key saved and encrypted successfully",
      },
      saveError: {
        ru: "Ошибка при сохранении ключа",
        en: "Failed to save API key",
      },
      currentKey: { ru: "Текущий ключ:", en: "Current key:" },
      replaceKeyPlaceholder: {
        ru: "Заменить API ключ...",
        en: "Replace API key...",
      },
      providersCount: {
        ru: (count: number) => `${count} источника`,
        en: (count: number) => `${count} sources`,
      },
      enable: { ru: "Включить", en: "Enable" },
      disable: { ru: "Отключить", en: "Disable" },
      enabledBadge: { ru: "Включен", en: "Enabled" },
      disabledBadge: { ru: "Отключен", en: "Disabled" },
      testConnection: { ru: "Проверить связь", en: "Test connection" },
      testing: { ru: "Проверка...", en: "Testing..." },
      testSuccess: {
        ru: (ms: number) => `Доступен (${ms} мс)`,
        en: (ms: number) => `Connected (${ms} ms)`,
      },
      testFailed: { ru: "Ошибка подключения", en: "Connection failed" },
    },
    search: {
      orderTitle: {
        ru: "Порядок категорий в поиске «Все»",
        en: 'Category order in "All" search',
      },
      orderHint: {
        ru: "Настройте порядок отображения групп категорий при общем поиске.",
        en: "Configure the order of media type sections when searching All.",
      },
      sourcePriorityTitle: {
        ru: "Приоритет источников по типам",
        en: "Source priority by media type",
      },
      sourcePriorityHint: {
        ru: "Если в первом источнике ничего не найдено, поиск автоматически переходит к следующему.",
        en: "If no results are found in the primary source, search automatically falls back to the next one.",
      },
      moveUp: { ru: "Вверх", en: "Up" },
      moveDown: { ru: "Вниз", en: "Down" },
      saved: { ru: "Порядок сохранён", en: "Order saved" },
      prioritySaved: {
        ru: "Приоритет источников сохранён",
        en: "Source priority saved",
      },
      primary: { ru: "Основной", en: "Primary" },
      fallback: {
        ru: (order: number) => `Резервный (${order})`,
        en: (order: number) => `Backup (${order})`,
      },
    },
    backup: {
      title: {
        ru: "Резервное копирование и восстановление",
        en: "Backup and Restore",
      },
      exportTitle: { ru: "Экспорт резервной копии", en: "Export Backup" },
      exportDescription: {
        ru: "Создает полный автономный архив вашей медиатеки: базу данных SQLite и все скачанные обложки в оригинальном качестве.",
        en: "Creates a complete standalone archive of your media library: SQLite database and all downloaded covers in original quality.",
      },
      exportButton: { ru: "Скачать резервную копию", en: "Download Backup" },
      exporting: { ru: "Создание архива...", en: "Creating archive..." },
      restoreTitle: {
        ru: "Восстановление из копии",
        en: "Restore from Backup",
      },
      restoreDescription: {
        ru: "Восстановление полностью заменит текущую базу данных и сохраненные обложки данными из архива. Рекомендуется сначала сделать свежий бэкап.",
        en: "Restoring will completely replace the current database and saved covers with data from the archive. It is recommended to make a fresh backup first.",
      },
      selectFileButton: {
        ru: "Восстановить из файла...",
        en: "Restore from file...",
      },
      dangerZone: { ru: "Опасная зона", en: "Danger Zone" },
      confirmModalTitle: {
        ru: "Подтверждение восстановления",
        en: "Confirm Restore",
      },
      confirmModalWarning: {
        ru: "Вы уверены, что хотите восстановить данные из выбранного архива? Текущая база данных и все файлы обложек будут перезаписаны. Это действие необратимо.",
        en: "Are you sure you want to restore data from the selected archive? The current database and all cover files will be overwritten. This action cannot be undone.",
      },
      selectedFileLabel: { ru: "Выбранный файл:", en: "Selected file:" },
      confirmButton: {
        ru: "Да, восстановить базу",
        en: "Yes, restore database",
      },
      cancelButton: { ru: "Отмена", en: "Cancel" },
      restoring: { ru: "Восстановление...", en: "Restoring..." },
      restoreSuccess: {
        ru: "База данных успешно восстановлена. Страница будет перезагружена...",
        en: "Database restored successfully. The page will reload...",
      },
      resetTitle: { ru: "Удалить все данные", en: "Delete all data" },
      resetDescription: {
        ru: "Безвозвратно удаляет все тайтлы, коллекции, историю активности и сохранённые обложки.",
        en: "Permanently deletes all titles, collections, activity history, and saved covers.",
      },
      resetButton: {
        ru: "Сбросить медиатеку...",
        en: "Reset media library...",
      },
      resetConfirmTitle: { ru: "Полный сброс данных", en: "Factory reset" },
      resetWarning: {
        ru: "Это действие безвозвратно удалит всю медиатеку, списки, историю активности и файлы обложек. Отменить его будет невозможно.",
        en: "This will permanently delete your entire media library, lists, activity history, and cover files. This action cannot be undone.",
      },
      keepApiKeys: {
        ru: "Сохранить настроенные API-ключи",
        en: "Keep configured API keys",
      },
      typeToConfirm: {
        ru: "Введите проверочное слово, чтобы подтвердить удаление:",
        en: "Type the confirmation word to confirm deletion:",
      },
      confirmationWord: { ru: "УДАЛИТЬ", en: "DELETE" },
      resetConfirmButton: {
        ru: "Подтвердить полное удаление",
        en: "Confirm full deletion",
      },
      resetting: {
        ru: "Очистка медиатеки...",
        en: "Resetting media library...",
      },
      resetSuccess: {
        ru: "Медиатека успешно очищена",
        en: "Media library reset successfully",
      },
    },
    reading: {
      title: { ru: "Темп чтения", en: "Reading Speed" },
      description: {
        ru: "Индивидуальные параметры скорости чтения для расчета оставшегося времени и статистики.",
        en: "Personal reading speed settings used for estimated reading times and statistics.",
      },
      bookPageMinutes: {
        ru: "Скорость чтения книг (минут на страницу)",
        en: "Book reading speed (minutes per page)",
      },
      mangaChapterMinutes: {
        ru: "Скорость чтения манги (минут на главу)",
        en: "Manga reading speed (minutes per chapter)",
      },
      saveButton: { ru: "Сохранить", en: "Save" },
      savedToast: {
        ru: "Настройки темпа чтения успешно сохранены",
        en: "Reading speed settings saved successfully",
      },
    },
    apiTokens: {
      title: {
        ru: "API и персональные токены",
        en: "API & Personal Access Tokens",
      },
      description: {
        ru: "Используйте токены для интеграции с Home Assistant, Telegram-ботами, скриптами автоматизации и внешними приложениями.",
        en: "Use tokens for integration with Home Assistant, Telegram bots, automation scripts, and external apps.",
      },
      docsButton: {
        ru: "Документация API (/api/docs)",
        en: "API Documentation (/api/docs)",
      },
      createButton: {
        ru: "Сгенерировать новый токен",
        en: "Generate new token",
      },
      emptyState: {
        ru: "У вас пока нет активных API-токенов",
        en: "You don't have any active API tokens yet",
      },
      modalTitle: { ru: "Новый токен доступа", en: "New Access Token" },
      nameLabel: { ru: "Название токена", en: "Token Name" },
      namePlaceholder: {
        ru: "Например: Home Assistant в гостиной",
        en: "e.g. Home Assistant in living room",
      },
      expiresInDaysLabel: {
        ru: "Срок действия (дней, опционально)",
        en: "Expiration (days, optional)",
      },
      expiresInDaysPlaceholder: { ru: "Бессрочно", en: "No expiration" },
      generateSubmit: { ru: "Сгенерировать", en: "Generate" },
      generating: { ru: "Генерация...", en: "Generating..." },
      cancel: { ru: "Отмена", en: "Cancel" },
      copyToken: { ru: "Скопировать", en: "Copy" },
      copied: { ru: "Скопировано!", en: "Copied!" },
      warningTitle: { ru: "Внимание!", en: "Warning!" },
      warningText: {
        ru: "Обязательно скопируйте этот токен сейчас. В целях безопасности вы больше никогда не сможете его увидеть!",
        en: "Be sure to copy this token now. For security reasons, you will never be able to see it again!",
      },
      closeModal: { ru: "Я сохранил токен", en: "I've saved the token" },
      created: { ru: "Создан", en: "Created" },
      lastUsed: { ru: "Использовался", en: "Last used" },
      neverUsed: { ru: "Никогда", en: "Never" },
      expiresAt: { ru: "Истекает", en: "Expires" },
      neverExpires: { ru: "Бессрочно", en: "Never" },
      revokeConfirmTitle: { ru: "Отозвать токен?", en: "Revoke token?" },
      revokeConfirmText: {
        ru: "Все приложения, использующие этот токен, мгновенно потеряют доступ.",
        en: "All applications using this token will instantly lose access.",
      },
      revokeButton: { ru: "Отозвать", en: "Revoke" },
      revoking: { ru: "Отзыв...", en: "Revoking..." },
      revokedToast: {
        ru: "Токен успешно отозван",
        en: "Token revoked successfully",
      },
      createdToast: { ru: "Токен создан", en: "Token created successfully" },
    },
  },
  activity: {
    label: { ru: "Фоновые процессы", en: "Background processes" },
    open: { ru: "Открыть фоновые процессы", en: "Open background processes" },
    syncing: { ru: "Синхронизация", en: "Syncing" },
    loadingCover: { ru: "Загрузка обложки…", en: "Loading cover…" },
    coverMissing: { ru: "Обложка не найдена", en: "Cover not found" },
    loadingSeasons: { ru: "Загрузка сезонов…", en: "Loading seasons…" },
    empty: { ru: "Нет активных задач", en: "No active tasks" },
    emptyHint: {
      ru: "Добавьте тайтл из поиска — здесь появится прогресс синхронизации.",
      en: "Add a title from search — its sync progress will show up here.",
    },
    queued: { ru: "В очереди", en: "Queued" },
    completed: { ru: "Готово", en: "Done" },
    failed: { ru: "Ошибка", en: "Failed" },
    cancelled: { ru: "Отменено", en: "Cancelled" },
    cancel: { ru: "Отменить задачу", en: "Cancel task" },
    cancelAria: {
      ru: (title: string) => `Отменить синхронизацию «${title}»`,
      en: (title: string) => `Cancel sync of "${title}"`,
    },
  },
  backgroundJobs: {
    openWindow: { ru: "Открыть окно процессов", en: "Open processes window" },
    pendingCount: {
      ru: (count: number) => `Требуют уточнения: ${count}`,
      en: (count: number) => `Needs review: ${count}`,
    },
    banner: {
      ru: (count: number) =>
        `Найдено тайтлов, где алгоритм сомневается в точном совпадении: ${count}`,
      en: (count: number) =>
        `Titles found where the match algorithm is not fully confident: ${count}`,
    },
    gotoReview: { ru: "Перейти к выбору →", en: "Go to review →" },
    tabQueue: { ru: "Очередь задач", en: "Task queue" },
    tabReview: { ru: "Требуют уточнения", en: "Needs review" },
    reviewIntro: {
      ru: "Для этих тайтлов найдено несколько похожих вариантов или нет 100% уверенности. Выберите правильное совпадение или оставьте запись без привязки.",
      en: "Several similar options were found for these titles, or there is no full confidence. Pick the correct match or leave the entry unlinked.",
    },
    keepAll: { ru: "Оставить все как есть", en: "Keep all as is" },
    resolveAllPriority: {
      ru: "Выбрать все по приоритету",
      en: "Pick all by priority",
    },
    resolvedByPriorityToast: {
      ru: (applied: number, skipped: number) =>
        `Автоматически применено ${applied} совпадений. Пропущено ${skipped} тайтлов со слабыми совпадениями.`,
      en: (applied: number, skipped: number) =>
        `Applied ${applied} matches automatically. Skipped ${skipped} titles with weak matches.`,
    },
    delete: { ru: "Удалить", en: "Delete" },
    deletedToast: {
      ru: "Тайтл удален из библиотеки",
      en: "Title removed from the library",
    },
    yourEntryPrompt: {
      ru: "Ваша импортированная запись — выберите подходящее совпадение из списка ниже:",
      en: "Your imported entry — pick the matching title from the list below:",
    },
    findManually: { ru: "Найти вручную", en: "Find manually" },
    keepAsIs: { ru: "Оставить как есть", en: "Keep as is" },
    searchPlaceholder: {
      ru: "Введите альтернативное название и нажмите Enter…",
      en: "Type an alternative title and press Enter…",
    },
    suggestions: {
      ru: "Результаты ручного поиска",
      en: "Manual search results",
    },
    noCandidates: {
      ru: "Точных совпадений не найдено. Воспользуйтесь кнопкой «Найти вручную» или оставьте запись как есть.",
      en: 'No exact matches found. Use the "Find manually" button or keep the entry as is.',
    },
    choose: { ru: "✓ Выбрать", en: "✓ Choose" },
    refineBadge: { ru: "Уточнить", en: "Review" },
    openProcesses: {
      ru: "Открыть фоновые процессы",
      en: "Open background processes",
    },
    progress: {
      ru: (current: number, total: number) => `Прогресс: ${current} / ${total}`,
      en: (current: number, total: number) => `Progress: ${current} / ${total}`,
    },
    resolvedToast: {
      ru: (title: string) => `«${title}» привязан к выбранному источнику.`,
      en: (title: string) => `"${title}" was linked to the chosen source.`,
    },
    resolvedAsyncToast: {
      ru: "Выбор сохранен. Данные обновляются в фоне.",
      en: "Choice saved. Data refreshes in the background.",
    },
    throttleNotice: {
      ru: "Обогащение выполняется с безопасными паузами (2.5 сек между тайтлами), чтобы AniList, MangaDex и Shikimori не заблокировали ваш IP-адрес за спам запросами. Процесс идет автономно в фоне — вы можете закрыть это окно и продолжать пользоваться трекером.",
      en: "Enrichment runs with safe pauses (2.5 s between titles) so AniList, MangaDex and Shikimori never ban your IP for request spam. The process runs autonomously in the background — you can close this window and keep using the tracker.",
    },
    remainingMin: {
      ru: (min: number) => `~${min} мин. осталось`,
      en: (min: number) => `~${min} min remaining`,
    },
    keptToast: {
      ru: (count: number) => `Тайтлов оставлено без привязки: ${count}.`,
      en: (count: number) => `Titles left unlinked: ${count}.`,
    },
  },
  timeBudget: {
    filterTitle: { ru: "Сколько есть времени?", en: "Available time" },
    reset: { ru: "Сбросить", en: "Reset" },
    options: {
      all: { ru: "Все", en: "All" },
      m15: { ru: "15 м", en: "15 m" },
      m30: { ru: "30 м", en: "30 m" },
      m45: { ru: "45 м", en: "45 m" },
      h1: { ru: "1 ч", en: "1 h" },
      h1_5: { ru: "1.5 ч", en: "1.5 h" },
      h2_plus: { ru: "2 ч+", en: "2 h+" },
    },
    summary: {
      ru: (fitting: number, finishable: number) =>
        finishable > 0
          ? `Подходит тайтлов: ${fitting} • 🔥 Можно добить: ${finishable}`
          : `Подходит тайтлов: ${fitting}`,
      en: (fitting: number, finishable: number) =>
        finishable > 0
          ? `Matching titles: ${fitting} • 🔥 Can finish: ${finishable}`
          : `Matching titles: ${fitting}`,
    },
    emptyTitle: {
      ru: "Ничего не подошло",
      en: "Nothing fits this time slot",
    },
    emptyHint: {
      ru: (timeLabel: string) =>
        `За ${timeLabel} не нашлось подходящих тайтлов. Выберите больше времени или добавьте более короткие тайтлы.`,
      en: (timeLabel: string) =>
        `Nothing in your backlog fits in ${timeLabel}. Try choosing a longer time slot or adding shorter titles.`,
    },
    customTimePlaceholder: { ru: "Время…", en: "Time…" },
    unitMin: { ru: "мин", en: "min" },
    unitHours: { ru: "ч", en: "h" },
    applyCustomTime: { ru: "Применить", en: "Apply" },
  },
  staleTriage: {
    staleBadge: {
      ru: "без активности >180 дн.",
      en: "inactive >180 d",
    },
    staleTriageTitle: {
      ru: "Ревизия заброшенного бэклога",
      en: "Stale Backlog Triage",
    },
    staleTriageSubtitle: {
      ru: "Тайтлы в процессе, к которым вы давно не возвращались. Разгрузите список в 1 клик.",
      en: "In-progress titles you haven't returned to in a while. Declutter your list in 1 click.",
    },
    threshold90: {
      ru: "90 дней (3 мес)",
      en: "90 days (3 mo)",
    },
    threshold180: {
      ru: "180 дней (полгода)",
      en: "180 days (6 mo)",
    },
    threshold365: {
      ru: "1 год (365 дн.)",
      en: "1 year (365 d)",
    },
    foundCount: {
      ru: (count: number) => `Найдено висяков: ${count}`,
      en: (count: number) => `Stale items found: ${count}`,
    },
    daysInactive: {
      ru: (days: number, date: string) => `⏱ Без активности: ${days} дн. (с ${date})`,
      en: (days: number, date: string) => `⏱ Inactive: ${days} d (since ${date})`,
    },
    actionFocus: {
      ru: "В фокус",
      en: "Focus",
    },
    actionOnHold: {
      ru: "На паузу",
      en: "Pause",
    },
    actionDrop: {
      ru: "Бросить",
      en: "Drop",
    },
    actionToPlanned: {
      ru: "В планы",
      en: "To Planned",
    },
    triageCompleteTitle: {
      ru: "🎉 Отличная работа!",
      en: "🎉 Great job!",
    },
    triageCompleteText: {
      ru: (threshold: number) =>
        `В бэклоге нет заброшенных тайтлов старше ${threshold} дней. Внимание свободно для актуальных историй.`,
      en: (threshold: number) =>
        `There are no abandoned titles older than ${threshold} days in your backlog. Attention is free for current stories.`,
    },
    toastFocus: {
      ru: "Возвращено в фокус",
      en: "Returned to focus",
    },
    toastOnHold: {
      ru: "Отложено на паузу",
      en: "Paused",
    },
    toastDropped: {
      ru: "Помечено как брошенное",
      en: "Marked as dropped",
    },
    toastPlanned: {
      ru: "Перенесено в планы",
      en: "Moved to planned",
    },
    triageActionLink: {
      ru: "Провести ревизию заброшенных тайтлов →",
      en: "Review abandoned titles →",
    },
  },
  errors: {
    unexpected: {
      ru: "Произошла непредвиденная ошибка.",
      en: "Something went wrong. Please try again.",
    },
    requestFailed: {
      ru: "Не удалось выполнить запрос.",
      en: "The request could not be completed.",
    },
  },
} as const;

type Leaf = {
  ru: string | ((...args: never[]) => string) | readonly string[] | string[];
  en: string | ((...args: never[]) => string) | readonly string[] | string[];
};

/** Strips the pair wrapper, leaving the shape the UI actually indexes into. */
type Unpair<T> = T extends Leaf
  ? T extends { ru: infer R }
    ? R
    : never
  : { [K in keyof T]: Unpair<T[K]> };

/** Literal types widened so the resolved dictionary stays assignable and IDE-completable. */
type Widen<T> = T extends string
  ? string
  : T extends readonly (infer E)[]
    ? string[]
    : T extends (...args: infer A) => infer R
      ? (...args: A) => Widen<R>
      : { [K in keyof T]: Widen<T[K]> };

export type Dictionary = Widen<Unpair<typeof translations>>;

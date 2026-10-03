import { getExternalDetails } from "$shared/api/api";
import type { ExternalMedia, SearchMediaType } from "$shared/types";
import { createPrefetchCache } from "$shared/utils/prefetchCache";

// Внешние детали никогда не пишутся в БД: они принадлежат результату поиска, а не
// библиотеке. Тот же in-memory guard, что у библиотечного детайла; 10 минут — как у
// серверного кэша агрегатора.
const DETAILS_TTL_MS = 10 * 60 * 1000;

const detailsCache = createPrefetchCache<ExternalMedia>(DETAILS_TTL_MS);

/** Ключ кэша: один и тот же тайтл из разных источников — это разные запросы. */
function detailsKey(type: string, item: ExternalMedia): string {
    return `${type}:${item.externalSource ?? ""}:${item.externalId || item.title}`;
}

/**
 * Полные метаданные результата поиска.
 *
 * getExternalDetails глотает transport-ошибки и отдаёт null, поэтому null
 * пробрасывается как rejection: иначе минутная недоступность провайдера залипла бы
 * в кэше на все 10 минут. Вызывающий ловит ошибку сам и показывает то, что уже есть
 * из результата поиска.
 */
export async function loadExternalDetails(
    type: SearchMediaType,
    item: ExternalMedia,
): Promise<ExternalMedia> {
    return detailsCache.load(detailsKey(type, item), () =>
        getExternalDetails(
            type,
            item.externalId,
            item.title,
            item.externalSource ?? undefined,
        ).then((result) => {
            if (!result) throw new Error("External details unavailable");
            return result;
        }),
    );
}
import Foundation
import Ingestion
import Persistence
import Query

struct AppContainer {
    let dataService: AppDataService

    static func live() throws -> AppContainer {
        let database = try LiveDatabase(configuration: try LiveDatabase.appSupportConfiguration())
        let sourceRegistry = StaticSourceRegistry()
        let dashboardQuery = LiveDashboardQueryService(analytics: database)
        let sourceHealthQuery = LiveSourceHealthQueryService(analytics: database)
        let importCoordinator = ImportCoordinator(
            registry: sourceRegistry,
            discovery: DefaultSourceDiscovery(),
            deduplicator: NoOpDeduplicator(),
            persistence: database
        )
        let readModelService = AppReadModelService(
            sourceRegistry: sourceRegistry,
            dashboardQuery: dashboardQuery,
            sourceHealthQuery: sourceHealthQuery,
            userDefaults: .standard
        )
        return AppContainer(
            dataService: AppDataService(
                importCoordinator: importCoordinator,
                readModelService: readModelService,
                quotaService: LaifuyouQuotaService(),
                groupQuotaSummaryReadModelService: GroupQuotaSummaryReadModelService(),
                menuBarSummaryReadModelService: MenuBarSummaryReadModelService()
            )
        )
    }

    @MainActor
    func makeAppState() -> AppState {
        AppState(dataService: dataService)
    }
}

requirejs_config =
    baseUrl: 'vendor'
    paths:
        app: '../js'
    shim:
        backbone:
            deps: ['underscore', 'jquery']
            exports: 'Backbone'
        typeahead:
            deps: ['jquery']
        TweenLite:
            deps: ['CSSPlugin', 'EasePack']

requirejs.config requirejs_config

PAGE_SIZE = 200

window.get_ie_version = ->
    is_internet_explorer = ->
        window.navigator.appName is "Microsoft Internet Explorer"

    if not is_internet_explorer()
        return false

    matches = new RegExp(" MSIE ([0-9]+)\\.([0-9])").exec window.navigator.userAgent
    return parseInt matches[1]

requirejs ['app/map', 'app/models', 'app/widgets', 'app/views', 'app/router', 'app/p13n', 'app/map', 'backbone', 'backbone.marionette', 'jquery', 'app/uservoice'], (map_stuff, Models, widgets, views, Router, p13n, MapView, Backbone, Marionette, $, uservoice) ->

    class AppControl
        constructor: (options) ->
            # Units currently on the map
            @units = options.unit_collection
            # Services in the cart
            @services = options.service_collection
            # Selected units (always of length one)
            @selected_unit = options.selected_unit
        setUnits: (units) ->
            @services.set []
            @units.reset units.toArray()
        selectUnit: (unit) ->
            @selected_unit.reset [unit]
        clearSelectedUnit: (unit) ->
            @selected_unit.reset []
        removeUnit: (unit) ->
            @units.remove unit
            selected = @selected_unit.first()
            if unit == selected
                @clearSelectedUnit()
        addService: (service) ->
            @services.add(service)

            unit_list = new models.UnitList pageSize: PAGE_SIZE
            service.set 'units', unit_list

            unit_list.setFilter 'service', service.id
            unit_list.setFilter 'only', 'name,location'

            fetch_opts =
                # todo: re-enable
                #spinner_target: spinner_target
                success: =>
                    pages_left = unit_list.fetchNext fetch_opts
                    #@selected_services.trigger 'change'
                    # todo: re-enable bounds fitting
                    # if not pages_left
                    #     @refit_bounds()

            unit_list.on 'add', (unit, unit_list, options) =>
                @units.add unit
            unit_list.fetch fetch_opts

        removeService: (service_id) ->
            service = @services.get(service_id)
            service.get('units').each (unit) =>
                @removeUnit unit
            @services.remove service

    app = new Backbone.Marionette.Application()

    app.addInitializer (opts) ->
        app_models =
            service_list: new Models.ServiceList()
            selected_services: new Models.ServiceList()
            selected_unit: new Models.UnitList()
            shown_units: new Models.UnitList()

        app_control = new AppControl
            unit_collection: app_models.shown_units
            service_collection: app_models.selected_services
            selected_unit: app_models.selected_unit

        map_view = new MapView
            units: app_models.shown_units
            services: app_models.selected_services
            selected_unit: app_models.selected_unit
        map = map_view.map
        window.map = map

        app_state = new views.AppState
            service_list: app_models.service_list
            selected_services: app_models.selected_services
            map_view: map_view

        @commands.setHandler "addService", (service) -> app_control.addService service
        @commands.setHandler "removeService", (service_id) -> app_control.removeService service_id
        @commands.setHandler "selectUnit", (unit) -> app_control.selectUnit unit
        @commands.setHandler "setUnits", (units) -> app_control.setUnits units

        service_sidebar_view = new views.ServiceSidebarView
            parent: app_state
            service_tree_collection: app_models.service_list
            selected_services: app_models.selected_services
            selected_unit: app_models.selected_unit

        app_state.service_sidebar = service_sidebar_view

        (@getRegion 'map').show map_view
        (@getRegion 'navigation').show service_sidebar_view
        (@getRegion 'landing_logo').show new views.LandingTitleView
        (@getRegion 'logo').show new views.TitleView

        customization = new views.CustomizationLayout
        (@getRegion 'customization').show customization
        customization.cart.show new views.ServiceCart
            collection: app_state.selected_services
            app: app_state
        customization.language.show new views.LanguageSelectorView
            p13n: p13n

        f = -> app_state.clear_landing_page()
        $('body').one "keydown", f
        map_view.map.addOneTimeEventListener
            'zoomstart': f
            'mousedown': f

        router = new Router()
        Backbone.history.start()

    app.addRegions
        navigation: '#navigation-region'
        customization: '#customization'
        landing_logo: '#landing-logo'
        logo: '#persistent-logo'
        map: '#app-container'
    window.app = app

    # We wait for p13n/i18next to finish loading before firing up the UI
    $.when(p13n.deferred).done ->
        app.start()
        uservoice.init(p13n.get_language())

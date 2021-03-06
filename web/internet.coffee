uuid = null
ResolvedIPs = {}

formatByteCount = (bytes, unit = 1000, force = -1) ->
    if bytes < unit
        return bytes + " B"

    if force >= 0
        exp = force
    else
        exp = Math.floor(Math.log(bytes) / Math.log(unit))

    filler = ''
    if unit == 1000
        units = "kMGTPE"
    else
        units = "KMGTPE"
        if exp > 0
            filler = "i"


    suffix = ' ' + units.charAt(exp - 1) + filler + 'B'

    return (bytes / Math.pow(unit, exp)).toFixed(2) + suffix

byteColor = (bytes, direction) ->
    maxIn = 14107200
    maxOut = 665360

    if direction == "down"
        r = bytes / maxIn
    else
        r = bytes / maxOut


    return $.xcolor.darken([Math.floor(255 * r), Math.floor(255 * (1 - r)), 0], 2).toString()

capitalize = (s) ->
    return s.charAt(0).toUpperCase() + s[1..-1]

ellipsize = (s, length) ->
    if s.length > length
        s[0...length] + "…"
    else
        s

makeTableScroll = (el) ->
    maxRows = el.getAttribute("data-max-rows")
    wrapper = el.parentNode
    rowsInTable = el.rows.length
    height = 0
    if rowsInTable > maxRows
        for row in $(el.rows)[0...maxRows]
            height += row.clientHeight
        wrapper.style.height = "#{height}px"

class Page
    constructor: (@active_section) ->
        $("#display_option").change =>
            @.updateStatistics()

        $("table.sortable").each (_, obj) ->
            $(obj).tablesorter()

        makeTableScroll $("#clients table")[0]

        $("#link_memory").click (e) =>
            e.preventDefault()
            @.displayMemoryUsage()

        $("#link_dhcp").click (e) =>
            e.preventDefault()
            @.displayDHCP()

        $("#link_nat").click (e) =>
            e.preventDefault()
            @.displayNAT()

        $("#link_main").click (e) =>
            e.preventDefault()
            @.displayMain()

        $("#link_tools").click (e) =>
            e.preventDefault()
            @.displayTools()

        $("#start_capture").click ->
            $("#start_capture")[0].disabled = true
            $("#stop_capture")[0].disabled = false
            startCapture()

        $("#stop_capture").click ->
            $("#start_capture")[0].disabled = false
            $("#stop_capture")[0].disabled = true
            stopCapture()

        $("h1").click ->
            $(@).toggleClass("inactive")
            $(@).find("+ div").slideToggle 250, ->

        @graph = displayTrafficGraph()
        displaySystemData()


    displayMemoryUsage: =>
        $(".system_information table.memory_usage").fadeToggle(250)

    displayMain: =>
        @active_section.fadeOut 250, =>
            @active_section = $("#main_display")
            $("#main_display").fadeIn(250, =>
                @graph.updateDimensions()
            )

    displayTools: =>
        @active_section.fadeOut 250, =>
            @active_section = $("#tools")
            $("#tools").fadeIn 250

    displayDHCP: =>
        @active_section.fadeOut 250, =>
            @active_section = $("#dhcp")
            @active_section.fadeIn 250

    displayNAT: =>
        table = $("#nat table#active_connections")
        table.find("tbody tr").remove()
        $("<tr><td>Loading...</td><td>Loading...</td><td>Loading...</td><td>Loading...</td></tr>").appendTo(table.find("tbody"))
        @active_section.fadeOut 250, =>
            @active_section = $("#nat")
            $("#nat").fadeIn(250)

        $.getJSON "/nat.json", (data) ->
            table.find("tbody tr").remove()
            for entry in data
                row = $("<tr class='#{entry.State.toLowerCase()}'><td>#{entry.Protocol}</td><td><a href=''>#{entry.SourceAddress}:#{entry.SourcePort}</a></td><td><a href=''>#{entry.DestinationAddress}:#{entry.DestinationPort}</a></td><td>#{entry.State}</td></tr>")
                row.appendTo(table.find("tbody"))
            table.trigger("update")

    updateStatistics: =>
        exp = $("#display_option").val()
        rows = $("#traffic_stats > tbody > tr")[1..-1]
        for row in rows
            for td in $(row).children()[1..-1]
                td.innerHTML = formatByteCount(td.getAttribute("data-bytes"), 1000, exp)
        return null

startCapture = ->
    $.get "/uuid", "", (data) ->
        uuid = data
        window.location = "/traffic_capture?uuid=#{data}&interface=#{$("#capture_interface").val()}"

stopCapture = ->
    $.get "/stop_capture", {uuid}


class TrafficGraph
    constructor: (renderTarget) ->
        @update = true
        @backlog = []
        @chart = new Highcharts.Chart(
            chart:
                animation:
                    duration: 400
                    easing: 'linear'
                renderTo: renderTarget[0]
                type: 'areaspline'
                marginLeft: 80
                marginRight: 10
                showAxes: true
                alignTicks: false
                zoomType: "x"
            title:
                text: null
            xAxis:
                type: 'datetime'
            yAxis: [
                {
                    title: false
                    showFirstLabel: false
                    height: 200
                    labels:
                        formatter: ->
                            formatByteCount(this.value, 1000) + "/s"
                }
                {
                    title: false
                    showFirstLabel: true
                    labels:
                        formatter: ->
                            formatByteCount(-this.value, 1000) + "/s"
                    offset: 0
                    top: 210
                    height: 200
                    max: 0
                    threshold: 0
                    endOnTick: true
                    startOnTick: true
                }
            ]
            plotOptions:
                turboThreshold: 1
                areaspline:
                    fillOpacity: 0.5
            tooltip:
                crosshairs: true
                shared: true
            legend:
                enabled: true
                layout: 'horizontal'
                align: 'center'
                verticalAlign: 'bottom'
                borderWidth: 0
            exporting:
                enabled: false
            credits:
                enabled: false
            series: [
                {
                    name: 'Downstream'
                    color: "#52b86f"
                    yAxis: 0
                    data: []
                }
                {
                    name: "Upstream"
                    color: "#aa4643"
                    yAxis: 1
                    data: []
                    fillOpacity: 0.2
                }
            ]
        )

        renderTarget.hover(
            => @update = false
            => @update = true
        )

    addPoint: (data) =>
        if @update == true
            for index, otherData of @backlog
                time = new Date(otherData.Time).getTime()
                # Using the index here, because series1.data.length
                # will not update until we call chart.redraw
                shift = (@chart.series[0].data.length + index) > 60
                @chart.series[0].addPoint([time, otherData.BPSIn], false, shift)
                @chart.series[1].addPoint([time, -otherData.BPSOut], false, shift)
                @backlog = []

            shift = @chart.series[0].data.length > 60
            time = new Date(data.Time).getTime()
            console.log(time)
            @chart.series[0].addPoint([time, data.BPSIn], false, shift)
            @chart.series[1].addPoint([time, -data.BPSOut], false, shift)
            @chart.redraw()
        else
            @backlog.push(data)
            @backlog.shift() if @backlog.length > 60

    updateDimensions: =>
        # Use the chart's container's parent to get the new
        # size.
        container = $(@chart.container).parent()
        @chart.setSize(container.width(), container.height(), false)

updateThisMonthsStatistics = (data) ->
    exp = $("#display_option").val()
    thisMonth = $("#traffic_stats > tbody > tr:first > td")
    thisMonth[1].innerHTML = formatByteCount(data.In, 1000, exp)
    thisMonth[2].innerHTML = formatByteCount(data.Out, 1000, exp)

resolveIP = (ip) ->
    return if ResolvedIPs[ip]
    $.ajax "/resolve_ip/#{ip}", success: (data) ->
        ResolvedIPs[ip] = data


updateClients = (data) ->
    row = $("#clients tr[data-ip='#{data.Host}']")
    resizeGraph = false

    if row.length == 0
        return false if (data.BPSOut == 0 && data.BPSIn == 0) || data.Host == "total"
        resolveIP(data.Host)

        row = $("<tr data-hostname='#{data.Host}' data-ip='#{data.Host}'><td><a href='' title='#{data.Host} &lt;#{data.Host}&gt;'>#{ellipsize(data.Host, 25)}</a></td><td class='up'>↗<span class='up'>0 B/s</span></td><td class='down'>↙<span class='down'>0 B/s</span></td></tr>")
        row.appendTo("#clients tbody")

        resizeGraph = true
    else
        if (hostname = ResolvedIPs[data.Host]) && (row.attr("data-hostname") != hostname)
            row.attr("data-hostname", hostname)
            row.find("td a").attr("title", "#{hostname} <#{data.Host}>")
            row.find("td a").html(ellipsize(hostname, 25))
            resizeGraph = true
    up = row.find("span.up")
    down = row.find("span.down")

    up.html(formatByteCount(data.BPSOut, 1000) + "/s")
    down.html(formatByteCount(data.BPSIn, 1000) + "/s")

    up.css("color", byteColor(data.BPSOut, "up"))
    down.css("color", byteColor(data.BPSIn, "down"))

    return resizeGraph

$ ->
    page = new Page($("#main_display"))
    page.updateStatistics()

displayTrafficGraph = ->
    graph = new TrafficGraph($("#live_graph"))

    source = new EventSource("/live/traffic_data/")

    source.onmessage = (event) ->
        stats = $.parseJSON(event.data)
        for stat in stats
            if stat.Host == "total"
                console.log(stat)
                graph.addPoint(stat)
                updateThisMonthsStatistics(stat)

            # Adding a new row might change the graph's available
            # width, so resize the graph.
            newRow = updateClients(stat) || newRow
        if newRow
            graph.updateDimensions()
    return graph

displaySystemData = ->
    source = new EventSource("/live/system_data/")

    source.onmessage = (event) ->
        data = $.parseJSON(event.data)

        updateMAC(data["Interfaces"], "LAN")
        updateMAC(data["Interfaces"], "WAN")

        updateIPs(data["Interfaces"], "LAN")
        updateIPs(data["Interfaces"], "WAN")

        updateMemoryStat(data["Memory"], "used")
        updateMemoryStat(data["Memory"], "buffers")
        updateMemoryStat(data["Memory"], "cache")

updateMAC = (interfaces, iface) ->
    $("#mac_" + iface.toLowerCase()).html(interfaces[iface]["MAC"])

updateIPs = (interfaces, iface) ->
    $("#ips_" + iface.toLowerCase()).html(interfaces[iface]["IPs"].join("<br>"))

updateMemoryStat = (memory, stat) ->
    el = $(".system_information .progressbar .#{stat.toLowerCase()}")
    stat = capitalize(stat)
    percentage = (memory[stat] / memory["Total"]) * 100
    text = formatByteCount(memory[stat], 1024, -1)

    el.css("width", percentage + "%")
    el.attr("title", text + " used (#{percentage.toFixed(2)}%)")
    $(".system_information .memory_usage .#{stat.toLowerCase()}").html(text + " (" + percentage.toFixed(2) + "%)")

Highcharts.Point.prototype.tooltipFormatter = (useHeader) ->
    point = this
    series = point.series
    return [
        '<span style="color:' + series.color + '">',
        (point.name || series.name),
        '</span>: ',
        '<b>',
        formatByteCount(Math.abs(point.y), 1000) + "/s",
        '</b><br />'
    ].join('')

jQuery.fx.interval = 50
Highcharts.setOptions({
    global: {
        useUTC: false
    }
})

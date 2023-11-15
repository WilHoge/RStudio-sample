# Shiny app that reads a path and shows a listdir()

library(shiny)
ui <- fluidPage(
  "List directory",
  textInput("path", "Enter path:"),
  verbatimTextOutput("input$path"),
  textOutput("listing")
)
server <- function(input, output, session) {
  observeEvent(input$path, {
    print(paste0("Your input: ", input$path))
  })
  
  output$listing <- renderText({
    paste( list.files(input$path,all.files = TRUE),sep="\n")
    # Sys.getenv(input$path). # show env.var instead of fs path
    # .libPaths()
  })
}
shinyApp(ui, server)
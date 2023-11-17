library(ggplot2)

g_faceted<-ggplot(data=diamonds, aes(x=carat, y=price, color=color)) + geom_point(alpha=.1) + ggtitle("The impact of diamond size on price") + facet_grid(. ~clarity, labeller = label_both)
g_faceted

ggsave("plot.png", width=5, height=5)

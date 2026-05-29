FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY mywebapp/mvnw .
COPY mywebapp/pom.xml .
RUN chmod +x mvnw && ./mvnw dependency:go-offline -q
COPY mywebapp/src ./src
RUN ./mvnw package -DskipTests -q
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /build/target/mywebapp.jar app.jar

RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
FROM eclipse-temurin:21-jdk-alpine AS builder

RUN apk add --no-cache maven

WORKDIR /build

COPY mywebapp/pom.xml .
RUN mvn dependency:go-offline -q

COPY mywebapp/src ./src
RUN mvn package -DskipTests -q
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /build/target/mywebapp.jar app.jar

RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]